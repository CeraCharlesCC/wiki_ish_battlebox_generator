import 'package:meta/meta.dart';

import 'wikitext_template_parser.dart';

enum NormalizationMode { inlineText, listItem, media }

@immutable
class NormalizationResult {
  final String normalizedText;
  final List<String> unparsedFragments;
  final String? firstOffendingToken;

  const NormalizationResult({
    required this.normalizedText,
    this.unparsedFragments = const [],
    this.firstOffendingToken,
  });
}

class WikitextNormalizer {
  final WikitextTemplateParser _templateParser;

  const WikitextNormalizer({WikitextTemplateParser? templateParser})
      : _templateParser = templateParser ?? const WikitextTemplateParser();

  NormalizationResult normalize(
    String raw, {
    required NormalizationMode mode,
  }) {
    if (raw.trim().isEmpty) {
      return const NormalizationResult(normalizedText: '');
    }

    var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final fragments = <String>[];
    String? firstOffendingToken;

    void addFragment(String fragment, {String? offendingToken}) {
      final trimmed = fragment.trim();
      if (trimmed.isEmpty) {
        return;
      }
      fragments.add(trimmed);
      firstOffendingToken ??= offendingToken;
    }

    text = text.replaceAllMapped(RegExp(r'<!--[\s\S]*?-->'), (match) {
      addFragment(match.group(0)!, offendingToken: 'comment');
      return '';
    });

    text = text.replaceAllMapped(
      RegExp(r'<ref\b[^>]*>[\s\S]*?<\/ref>', caseSensitive: false),
      (match) {
        addFragment(match.group(0)!, offendingToken: 'ref');
        return '';
      },
    );

    text = text.replaceAllMapped(
      RegExp(r'<ref\b[^>]*\/>', caseSensitive: false),
      (match) {
        addFragment(match.group(0)!, offendingToken: 'ref');
        return '';
      },
    );

    var index = 0;
    while (index < text.length) {
      final openIndex = text.indexOf('{{', index);
      if (openIndex == -1) {
        break;
      }
      final closeIndex = _findClosingTemplate(text, openIndex + 2);
      if (closeIndex == -1) {
        addFragment(
          text.substring(openIndex),
          offendingToken: 'unbalanced-template',
        );
        text = text.substring(0, openIndex);
        break;
      }

      final rawTemplate = text.substring(openIndex, closeIndex + 2);
      final replacement = _normalizeTemplate(
        rawTemplate,
        mode: mode,
        addFragment: addFragment,
      );

      text = text.replaceRange(openIndex, closeIndex + 2, replacement);
      index = openIndex + replacement.length;
    }

    return NormalizationResult(
      normalizedText: _cleanupWhitespace(text),
      unparsedFragments: fragments,
      firstOffendingToken: firstOffendingToken,
    );
  }

  String _normalizeTemplate(
    String rawTemplate, {
    required NormalizationMode mode,
    required void Function(String fragment, {String? offendingToken}) addFragment,
  }) {
    final parsed = _templateParser.parse(rawTemplate);
    if (parsed == null) {
      addFragment(rawTemplate, offendingToken: 'template');
      return '';
    }

    final normalizedName = _normalizeName(parsed.templateName);

    switch (normalizedName) {
      case 'plainlist':
      case 'plain list':
      case 'bulletlist':
      case 'bullet list':
      case 'flatlist':
      case 'indented plainlist':
      case 'collapsible list':
        final items = _extractListItems(normalizedName, parsed);
        final normalizedItems = <String>[];
        for (final item in items) {
          final nested = normalize(
            item,
            mode: NormalizationMode.inlineText,
          );
          for (final fragment in nested.unparsedFragments) {
            addFragment(
              fragment,
              offendingToken: nested.firstOffendingToken,
            );
          }
          final value = nested.normalizedText.trim();
          if (value.isNotEmpty) {
            normalizedItems.add(value);
          }
        }

        if (normalizedItems.isEmpty) {
          return '';
        }
        return '\n${normalizedItems.join('\n')}\n';
      case 'endplainlist':
        return '';
      case 'hr':
        return '\n';
      case 'snd':
        return ' – ';
      case 'age in years, months, weeks and days':
      case 'age in years months weeks and days':
        return '';
      case 'nowrap':
      case 'nobold':
        if (parsed.unnamedParams.isEmpty) {
          return '';
        }
        final nested = normalize(
          parsed.unnamedParams.first,
          mode: NormalizationMode.inlineText,
        );
        for (final fragment in nested.unparsedFragments) {
          addFragment(
            fragment,
            offendingToken: nested.firstOffendingToken,
          );
        }
        return nested.normalizedText;
      case 'flagicon':
      case 'flag icon':
        return rawTemplate;
      case 'flagicon image':
        return '';
      case 'flag':
      case 'flagcountry':
      case 'flagdeco':
        return _extractFlagText(parsed);
      case 'multiple image':
        return _extractFirstImage(parsed) ?? '';
      default:
        addFragment(rawTemplate, offendingToken: parsed.templateName.trim());
        return '';
    }
  }

  List<String> _extractListItems(String name, ParsedTemplateInvocation parsed) {
    final items = <String>[];

    void appendFromLine(String line) {
      var value = line.trim();
      if (value.isEmpty) {
        return;
      }
      value = value.replaceFirst(RegExp(r'^[*#]+\s*'), '').trim();
      if (value.isEmpty) {
        return;
      }
      items.add(value);
    }

    if (name == 'plainlist' || name == 'plain list' || name == 'indented plainlist') {
      final combined = parsed.unnamedParams.join('\n');
      if (combined.trim().isNotEmpty) {
        for (final line in combined.split('\n')) {
          appendFromLine(line);
        }
      }
      return items;
    }

    if (name == 'bulletlist' || name == 'bullet list' || name == 'flatlist') {
      for (final value in parsed.unnamedParams) {
        for (final line in value.split('\n')) {
          appendFromLine(line);
        }
      }
      return items;
    }

    if (name == 'collapsible list') {
      for (final value in parsed.unnamedParams) {
        appendFromLine(value);
      }
      return items;
    }

    return items;
  }

  String _extractFlagText(ParsedTemplateInvocation parsed) {
    if (parsed.unnamedParams.isEmpty) {
      return '';
    }

    if (parsed.unnamedParams.length > 1) {
      return parsed.unnamedParams.last.trim();
    }

    return parsed.unnamedParams.first.trim();
  }

  String? _extractFirstImage(ParsedTemplateInvocation parsed) {
    for (var index = 1; index <= 9; index++) {
      final key = 'image$index';
      final value = parsed.namedParams[key]?.trim();
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

  String _cleanupWhitespace(String input) {
    final normalizedNewlines = input
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n');
    return normalizedNewlines.trim();
  }

  String _normalizeName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
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
