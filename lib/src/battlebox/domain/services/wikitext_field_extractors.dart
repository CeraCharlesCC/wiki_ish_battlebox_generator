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
  })  : _normalizer = normalizer ?? const WikitextNormalizer(),
        _scanner = scanner ?? const WikitextBalancedScanner(),
        _templateParser = templateParser ?? const WikitextTemplateParser();

  FieldExtractionResult extractCombatant(String raw) {
    return _extractListField(raw, family: FieldFamily.combatant);
  }

  FieldExtractionResult extractCommander(String raw) {
    return _extractListField(raw, family: FieldFamily.commander);
  }

  FieldExtractionResult extractStrength(String raw) {
    return _extractListField(raw, family: FieldFamily.strength);
  }

  FieldExtractionResult extractCasualties(String raw) {
    return _extractListField(raw, family: FieldFamily.casualties);
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
      final close = _findClosingTemplate(trimmed, 2);
      if (close != -1) {
        final token = trimmed.substring(0, close + 2);
        final parsed = _templateParser.parse(token);
        if (parsed != null &&
            _normalizeTemplateName(parsed.templateName) == 'multiple image') {
          image = _extractFirstImageFromParsedTemplate(parsed);
          final remainder = trimmed.substring(close + 2).trim();
          if (remainder.isNotEmpty) {
            fragments.add(remainder);
            firstOffendingToken ??= 'multiple image';
          }
        }
      }
    }

    if (image == null || image.trim().isEmpty) {
      final normalized =
          _normalizer.normalize(raw, mode: NormalizationMode.media);
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

  FieldExtractionResult _extractListField(
    String raw, {
    required FieldFamily family,
  }) {
    if (raw.trim().isEmpty) {
      return const FieldExtractionResult(
        items: [],
        unparsedFragments: [],
        firstOffendingToken: null,
        status: ImportFieldStatus.skipped,
      );
    }

    final normalized = _normalizer.normalize(raw, mode: NormalizationMode.listItem);
    final fragments = <String>[...normalized.unparsedFragments];
    var firstOffendingToken = normalized.firstOffendingToken;

    List<String> items;
    try {
      final normalizedForSplit = _normalizeSeparators(normalized.normalizedText);
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

    if ((family == FieldFamily.combatant || family == FieldFamily.commander) &&
        items.isNotEmpty) {
      items = items.map(_normalizeHeaderSpacing).toList();
    }

    return FieldExtractionResult(
      items: items,
      unparsedFragments: fragments,
      firstOffendingToken: firstOffendingToken,
      status: _resolveStatus(raw: raw, items: items, fragments: fragments),
    );
  }

  String _normalizeSeparators(String input) {
    return input
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<hr\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'\{\{\s*hr\s*\}\}', caseSensitive: false), '\n')
        .replaceAll('----', '\n');
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

  String _normalizeHeaderSpacing(String value) {
    return value.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
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

  String? _extractFirstImageFromParsedTemplate(ParsedTemplateInvocation parsed) {
    for (var index = 1; index <= 9; index++) {
      final value = parsed.namedParams['image$index']?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    for (final value in parsed.unnamedParams) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  int _findClosingTemplate(String input, int start) {
    var depth = 1;
    var i = start;

    while (i < input.length - 1) {
      if (input.substring(i, i + 2) == '{{') {
        depth++;
        i += 2;
        continue;
      }
      if (input.substring(i, i + 2) == '}}') {
        depth--;
        if (depth == 0) {
          return i;
        }
        i += 2;
        continue;
      }
      i++;
    }

    return -1;
  }
}
