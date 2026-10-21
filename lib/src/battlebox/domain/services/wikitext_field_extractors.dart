import 'package:meta/meta.dart';

import '../entities/wikitext_import_report.dart';
import 'wikitext_balanced_scanner.dart';
import 'wikitext_normalizer.dart';
import 'wikitext_template_parser.dart';

enum FieldFamily {
  combatant,
  commander,
  strength,
  casualties,
  genericList,
  genericSingle,
  mediaImage,
}

@immutable
class FieldExtractionResult {
  final List<String> items;
  final List<String> unparsedFragments;
  final String? firstOffendingToken;
  final ImportFieldStatus status;

  const FieldExtractionResult({
    required this.items,
    required this.unparsedFragments,
    required this.firstOffendingToken,
    required this.status,
  });
}

class WikitextFieldExtractors {
  final WikitextNormalizer _normalizer;
  final WikitextBalancedScanner _scanner;
  final WikitextTemplateParser _templateParser;

  const WikitextFieldExtractors({
    WikitextNormalizer? normalizer,
    WikitextBalancedScanner? scanner,
    WikitextTemplateParser? templateParser,
  }) : _normalizer = normalizer ?? const WikitextNormalizer(),
       _scanner = scanner ?? const WikitextBalancedScanner(),
       _templateParser = templateParser ?? const WikitextTemplateParser();

  FieldExtractionResult extractCombatant(String raw) {
    return _extractListField(raw);
  }

  FieldExtractionResult extractCommander(String raw) {
    return _extractListField(raw);
  }

  FieldExtractionResult extractStrength(String raw) {
    return _extractListField(raw);
  }

  FieldExtractionResult extractCasualties(String raw) {
    return _extractListField(raw);
  }

  /// Split ordinary list fields (such as dates, places and units) without
  /// rewriting references or unsupported templates they contain.
  FieldExtractionResult extractGenericList(String raw) {
    return _extractListField(raw);
  }

  FieldExtractionResult extractMediaImage(String raw) {
    if (raw.trim().isEmpty) {
      return const FieldExtractionResult(
        items: [],
        unparsedFragments: [],
        firstOffendingToken: null,
        status: ImportFieldStatus.skipped,
      );
    }

    final fragments = <String>[];
    String? firstOffendingToken;
    String? image;

    final trimmed = raw.trim();
    if (trimmed.startsWith('{{')) {
      final close = _scanner.findClosingTemplate(trimmed, 2);
      if (close != -1) {
        final token = trimmed.substring(0, close + 2);
        final parsed = _templateParser.parse(token);
        if (parsed != null &&
            _normalizeTemplateName(parsed.templateName) == 'multiple image') {
          image = parsed.firstImageValue;
          // The visual editor can only preview one image. Report the entire
          // source template so callers know additional images and formatting
          // would be lost without preserving the original wikitext.
          fragments.add(token);
          firstOffendingToken ??= 'multiple image';
          final remainder = trimmed.substring(close + 2).trim();
          if (remainder.isNotEmpty) {
            fragments.add(remainder);
          }
        }
      }
    }

    if (image == null || image.trim().isEmpty) {
      final normalized = _normalizer.normalize(
        raw,
        mode: NormalizationMode.media,
      );
      fragments.addAll(normalized.unparsedFragments);
      firstOffendingToken ??= normalized.firstOffendingToken;

      final candidates = _splitItemsBestEffort(normalized.normalizedText);
      if (candidates.isNotEmpty) {
        image = candidates.first;
      }
    }

    final items = <String>[];
    if (image != null && image.trim().isNotEmpty) {
      items.add(image.trim());
    }

    return FieldExtractionResult(
      items: items,
      unparsedFragments: fragments,
      firstOffendingToken: firstOffendingToken,
      status: _resolveStatus(raw: raw, items: items, fragments: fragments),
    );
  }

  FieldExtractionResult _extractListField(String raw) {
    if (raw.trim().isEmpty) {
      return const FieldExtractionResult(
        items: [],
        unparsedFragments: [],
        firstOffendingToken: null,
        status: ImportFieldStatus.skipped,
      );
    }

    final normalized = _normalizer.normalize(
      raw,
      mode: NormalizationMode.listItem,
    );
    final fragments = <String>[...normalized.unparsedFragments];
    var firstOffendingToken = normalized.firstOffendingToken;

    // Standalone wiki list markers are removed for the visual list editor.
    // Signal this formatting conversion instead of reporting a clean import.
    if (RegExp(r'(^|\n)\s*[*#]+\s+').hasMatch(raw) && fragments.isEmpty) {
      fragments.add(raw.trim());
      firstOffendingToken ??= 'list marker';
    }
    if (RegExp(r'<hr\s*/?>|----', caseSensitive: false).hasMatch(raw) &&
        fragments.isEmpty) {
      fragments.add(raw.trim());
      firstOffendingToken ??= 'horizontal rule';
    }

    List<String> items;
    try {
      final normalizedForSplit = _normalizeSeparators(
        normalized.normalizedText,
      );
      final segments = _scanner.splitTopLevel(
        normalizedForSplit,
        isSeparator: (state, index) =>
            state.isTopLevel && normalizedForSplit[index] == '\n',
      );
      items = _compactItems(segments);
    } on FormatException {
      if (normalized.normalizedText.trim().isNotEmpty) {
        fragments.add(normalized.normalizedText.trim());
      }
      firstOffendingToken ??= 'unbalanced-field';
      items = _splitItemsBestEffort(normalized.normalizedText);
    }

    return FieldExtractionResult(
      items: items,
      unparsedFragments: fragments,
      firstOffendingToken: firstOffendingToken,
      status: _resolveStatus(raw: raw, items: items, fragments: fragments),
    );
  }

  String _normalizeSeparators(String input) {
    // Only split on separators at the outer field level. A <br> inside a
    // citation, an unknown nested template or a link is source wikitext, not
    // a boundary between visual list items.
    final result = StringBuffer();
    final lower = input.toLowerCase();
    final refStart = RegExp(r'<ref\b', caseSensitive: false);
    final breakTag = RegExp(r'<(?:br|hr)\s*/?>', caseSensitive: false);
    final hrTemplate = RegExp(r'^\{\{\s*hr\s*\}\}$', caseSensitive: false);
    var index = 0;

    while (index < input.length) {
      if (input.startsWith('<!--', index)) {
        final end = input.indexOf('-->', index + 4);
        if (end < 0) {
          result.write(input.substring(index));
          break;
        }
        result.write(input.substring(index, end + 3));
        index = end + 3;
        continue;
      }
      if (refStart.matchAsPrefix(input, index) != null) {
        final tagEnd = input.indexOf('>', index + 4);
        if (tagEnd < 0) {
          result.write(input.substring(index));
          break;
        }
        final selfClosing = input
            .substring(index, tagEnd + 1)
            .trimRight()
            .endsWith('/>');
        final end = selfClosing ? -1 : lower.indexOf('</ref>', tagEnd + 1);
        if (!selfClosing && end < 0) {
          result.write(input.substring(index));
          break;
        }
        final last = selfClosing ? tagEnd + 1 : end + 6;
        result.write(input.substring(index, last));
        index = last;
        continue;
      }
      if (input.startsWith('{{', index)) {
        final end = _scanner.findClosingTemplate(input, index + 2);
        if (end < 0) {
          result.write(input.substring(index));
          break;
        }
        final value = input.substring(index, end + 2);
        result.write(hrTemplate.hasMatch(value) ? '\n' : value);
        index = end + 2;
        continue;
      }
      if (input.startsWith('[[', index)) {
        final end = input.indexOf(']]', index + 2);
        if (end < 0) {
          result.write(input.substring(index));
          break;
        }
        result.write(input.substring(index, end + 2));
        index = end + 2;
        continue;
      }

      final tag = breakTag.matchAsPrefix(input, index);
      if (tag != null) {
        result.write('\n');
        index = tag.end;
        continue;
      }
      if (input.startsWith('----', index)) {
        result.write('\n');
        index += 4;
        continue;
      }

      result.write(input[index]);
      index++;
    }

    return result.toString();
  }

  List<String> _compactItems(List<String> segments) {
    final items = <String>[];
    for (final segment in segments) {
      var value = segment.trim();
      if (value.isEmpty) {
        continue;
      }
      value = value.replaceFirst(RegExp(r'^[*#]+\s*'), '').trim();
      if (value.isEmpty) {
        continue;
      }
      items.add(value);
    }
    return items;
  }

  List<String> _splitItemsBestEffort(String text) {
    final normalized = _normalizeSeparators(text);
    return _compactItems(normalized.split('\n'));
  }

  ImportFieldStatus _resolveStatus({
    required String raw,
    required List<String> items,
    required List<String> fragments,
  }) {
    if (raw.trim().isEmpty) {
      return ImportFieldStatus.skipped;
    }
    if (items.isNotEmpty && fragments.isEmpty) {
      return ImportFieldStatus.parsed;
    }
    if (items.isNotEmpty && fragments.isNotEmpty) {
      return ImportFieldStatus.partial;
    }
    if (items.isEmpty && (fragments.isNotEmpty || raw.trim().isNotEmpty)) {
      return ImportFieldStatus.failed;
    }
    return ImportFieldStatus.skipped;
  }

  String _normalizeTemplateName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
