import 'package:meta/meta.dart';

import 'wikitext_balanced_scanner.dart';
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
  final WikitextBalancedScanner _scanner;
  final WikitextTemplateParser _templateParser;

  const WikitextNormalizer({
    WikitextBalancedScanner? scanner,
    WikitextTemplateParser? templateParser,
  }) : _scanner = scanner ?? const WikitextBalancedScanner(),
       _templateParser = templateParser ?? const WikitextTemplateParser();

  NormalizationResult normalize(String raw, {required NormalizationMode mode}) {
    if (raw.trim().isEmpty) {
      return const NormalizationResult(normalizedText: '');
    }

    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
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

    // Process templates from left to right without entering protected ref or
    // comment bodies. Keep their source markup and diagnostics in input order
    // (not one pass per token type); stripping them loses citations on export.
    final output = StringBuffer();
    final refStart = RegExp(r'<ref\b', caseSensitive: false);
    final lower = text.toLowerCase();
    var index = 0;
    while (index < text.length) {
      if (text.startsWith('<!--', index)) {
        final end = text.indexOf('-->', index + 4);
        if (end < 0) {
          addFragment(text.substring(index), offendingToken: 'comment');
          output.write(text.substring(index));
          break;
        }
        final comment = text.substring(index, end + 3);
        addFragment(comment, offendingToken: 'comment');
        output.write(comment);
        index = end + 3;
        continue;
      }

      if (refStart.matchAsPrefix(text, index) != null) {
        final tagEnd = text.indexOf('>', index + 4);
        if (tagEnd < 0) {
          addFragment(text.substring(index), offendingToken: 'ref');
          output.write(text.substring(index));
          break;
        }
        final selfClosing = text
            .substring(index, tagEnd + 1)
            .trimRight()
            .endsWith('/>');
        if (selfClosing) {
          final ref = text.substring(index, tagEnd + 1);
          addFragment(ref, offendingToken: 'ref');
          output.write(ref);
          index = tagEnd + 1;
          continue;
        }
        final end = lower.indexOf('</ref>', tagEnd + 1);
        if (end < 0) {
          addFragment(text.substring(index), offendingToken: 'ref');
          output.write(text.substring(index));
          break;
        }
        final ref = text.substring(index, end + 6);
        addFragment(ref, offendingToken: 'ref');
        output.write(ref);
        index = end + 6;
        continue;
      }

      if (!text.startsWith('{{', index)) {
        output.write(text[index]);
        index++;
        continue;
      }

      final closeIndex = _scanner.findClosingTemplate(text, index + 2);
      if (closeIndex == -1) {
        addFragment(
          text.substring(index),
          offendingToken: 'unbalanced-template',
        );
        // Do not throw away the unmatched template or the text following it.
        output.write(text.substring(index));
        break;
      }

      final rawTemplate = text.substring(index, closeIndex + 2);
      final replacement = _normalizeTemplate(
        rawTemplate,
        mode: mode,
        addFragment: addFragment,
      );

      output.write(replacement);
      index = closeIndex + 2;
    }

    return NormalizationResult(
      normalizedText: _cleanupWhitespace(output.toString()),
      unparsedFragments: fragments,
      firstOffendingToken: firstOffendingToken,
    );
  }

  String _normalizeTemplate(
    String rawTemplate, {
    required NormalizationMode mode,
    required void Function(String fragment, {String? offendingToken})
    addFragment,
  }) {
    final parsed = _templateParser.parse(rawTemplate);
    if (parsed == null) {
      addFragment(rawTemplate, offendingToken: 'template');
      return rawTemplate;
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
        // List templates are displayed as individual items, which cannot be
        // converted back to the exact original template on export.
        addFragment(rawTemplate, offendingToken: parsed.templateName.trim());
        final items = _extractListItems(normalizedName, parsed);
        final normalizedItems = <String>[];
        for (final item in items) {
          final nested = normalize(item, mode: NormalizationMode.inlineText);
          for (final fragment in nested.unparsedFragments) {
            addFragment(fragment, offendingToken: nested.firstOffendingToken);
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
        addFragment(rawTemplate, offendingToken: 'endplainlist');
        return '';
      case 'hr':
        addFragment(rawTemplate, offendingToken: 'hr');
        return '\n';
      case 'snd':
        addFragment(rawTemplate, offendingToken: 'snd');
        return ' – ';
      case 'age in years, months, weeks and days':
      case 'age in years months weeks and days':
        addFragment(rawTemplate, offendingToken: parsed.templateName.trim());
        return rawTemplate;
      case 'nowrap':
      case 'nobold':
        if (parsed.unnamedParams.isEmpty) {
          addFragment(rawTemplate, offendingToken: parsed.templateName.trim());
          return rawTemplate;
        }
        addFragment(rawTemplate, offendingToken: parsed.templateName.trim());
        final nested = normalize(
          parsed.unnamedParams.first,
          mode: NormalizationMode.inlineText,
        );
        for (final fragment in nested.unparsedFragments) {
          addFragment(fragment, offendingToken: nested.firstOffendingToken);
        }
        return nested.normalizedText;
      case 'flagicon':
      case 'flag icon':
        return rawTemplate;
      case 'flagicon image':
        addFragment(rawTemplate, offendingToken: 'flagicon image');
        return rawTemplate;
      case 'flag':
      case 'flagcountry':
      case 'flagdeco':
        addFragment(rawTemplate, offendingToken: parsed.templateName.trim());
        return _extractFlagText(parsed);
      case 'multiple image':
        // A single media field cannot represent every image/caption/size.
        addFragment(rawTemplate, offendingToken: 'multiple image');
        return rawTemplate;
      default:
        addFragment(rawTemplate, offendingToken: parsed.templateName.trim());
        return rawTemplate;
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

    if (name == 'plainlist' ||
        name == 'plain list' ||
        name == 'indented plainlist') {
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

  String _cleanupWhitespace(String input) {
    // Keep whitespace inside unsupported templates and references byte-for-
    // byte wherever possible. The extractors trim individual visual items.
    return input.trim();
  }

  String _normalizeName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
