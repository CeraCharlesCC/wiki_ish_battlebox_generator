import '../../../core/id_generator.dart';
import '../../application/ports/battlebox_serializer.dart';
import '../../domain/entities/battlebox_doc.dart';
import '../../domain/entities/column_model.dart';
import '../../domain/entities/rich_text_value.dart';
import '../../domain/entities/sections.dart';
import '../../domain/entities/wikitext_import_report.dart';
import '../../domain/services/battlebox_seed.dart';
import '../../domain/services/wikitext_balanced_scanner.dart';
import '../../domain/services/wikitext_field_extractors.dart';

/// Wikitext implementation of BattleboxSerializer.
///
/// Parses and exports battlebox documents in Wikipedia template format.
class WikitextBattleboxSerializer implements BattleboxSerializer {
  final IdGenerator _idGenerator;
  final WikitextBalancedScanner _balancedScanner;
  final WikitextFieldExtractors _fieldExtractors;

  WikitextBattleboxSerializer({
    IdGenerator? idGenerator,
    WikitextBalancedScanner? balancedScanner,
    WikitextFieldExtractors? fieldExtractors,
  }) : _idGenerator = idGenerator ?? const TimestampIdGenerator(),
       _balancedScanner = balancedScanner ?? const WikitextBalancedScanner(),
       _fieldExtractors = fieldExtractors ?? const WikitextFieldExtractors();

  @override
  BattleBoxDoc parse(String input) {
    final template = _extractTemplate(input);
    if (template == null) {
      return BattleboxSeed(_idGenerator).create();
    }

    Map<String, String> keyValues;
    ImportFieldReport? topLevelReport;

    try {
      keyValues = _parseKeyValuesBalanced(template);
      if (_isSuspiciousBalancedResult(template, keyValues)) {
        throw const FormatException(
          'Balanced parser produced too few infobox fields.',
        );
      }
    } on FormatException catch (error) {
      keyValues = _parseKeyValuesLegacy(template);
      topLevelReport = ImportFieldReport(
        key: '__infobox__',
        status: ImportFieldStatus.failed,
        parsedItemCount: 0,
        unparsedFragments: [template],
        firstOffendingToken: error.message.toString(),
      );
    }

    return _buildDocFromKeyValues(keyValues, topLevelReport: topLevelReport);
  }

  @override
  String export(BattleBoxDoc doc) {
    final buffer = StringBuffer();
    buffer.writeln('{{${doc.templateName}');
    _writeKey(buffer, 'conflict', doc.title);

    final media = doc.sections.whereType<MediaSection>().firstOrNull;
    if (media != null) {
      _writeKey(buffer, 'image', media.imageUrl ?? '');
      _writeKey(buffer, 'caption', media.caption ?? '');
      _writeKey(buffer, 'image_size', media.size ?? '');
      _writeKey(buffer, 'image_upright', media.upright ?? '');
    }

    _writeSingle(buffer, doc, 'Part of', 'partof');
    _writeList(buffer, doc, 'Date', 'date');
    _writeList(buffer, doc, 'Location', 'place');
    _writeSingle(buffer, doc, 'Coordinates', 'coordinates');
    _writeSingle(buffer, doc, 'Result', 'result');
    _writeSingle(buffer, doc, 'Territorial changes', 'territory');

    _writeMulti(buffer, doc, 'Combatants', 'combatant');
    _writeMulti(buffer, doc, 'Commanders and leaders', 'commander');
    _writeMulti(buffer, doc, 'Units', 'units');
    _writeMulti(buffer, doc, 'Strength', 'strength');
    _writeMulti(buffer, doc, 'Casualties', 'casualties');

    for (final entry in doc.customFields.entries) {
      _writeKey(buffer, entry.key, entry.value);
    }

    buffer.writeln('}}');
    return buffer.toString();
  }

  String? _extractTemplate(String input) {
    final lower = input.toLowerCase();
    final startIndex = lower.indexOf('{{infobox military conflict');
    if (startIndex == -1) {
      return null;
    }

    var depth = 0;
    var inComment = false;
    var inRef = false;
    var inTagHeader = false;
    var i = startIndex;

    while (i < input.length) {
      if (inComment) {
        if (wikitextStartsWithToken(input, i, '-->')) {
          inComment = false;
          i += 3;
          continue;
        }
        i++;
        continue;
      }

      if (inRef) {
        if (wikitextStartsWithTokenIgnoreCase(input, i, '</ref>')) {
          inRef = false;
          i += 6;
          continue;
        }
        i++;
        continue;
      }

      if (inTagHeader) {
        if (input[i] == '>') {
          inTagHeader = false;
        }
        i++;
        continue;
      }

      if (wikitextStartsWithToken(input, i, '<!--')) {
        inComment = true;
        i += 4;
        continue;
      }

      if (wikitextStartsWithTokenIgnoreCase(input, i, '<ref')) {
        final closing = input.indexOf('>', i + 1);
        if (closing == -1) {
          return null;
        }
        final tag = input.substring(i, closing + 1);
        final isSelfClosing = tag.trimRight().endsWith('/>');
        if (!isSelfClosing) {
          inRef = true;
        }
        i = closing + 1;
        continue;
      }

      if (input[i] == '<') {
        inTagHeader = true;
        i++;
        continue;
      }

      if (wikitextStartsWithToken(input, i, '{{')) {
        depth++;
        i += 2;
        continue;
      }

      if (wikitextStartsWithToken(input, i, '}}')) {
        depth--;
        if (depth == 0) {
          return input.substring(startIndex, i + 2);
        }
        if (depth < 0) {
          return null;
        }
        i += 2;
        continue;
      }

      i++;
    }

    return null;
  }

  Map<String, String> _parseKeyValuesBalanced(String template) {
    return _balancedScanner.parseInfoboxParams(template);
  }

  Map<String, String> _parseKeyValuesLegacy(String template) {
    final lines = template.split('\n');
    final values = <String, String>{};
    String? currentKey;
    final currentValue = StringBuffer();
    var nestedTemplateDepth = 0;

    var startIndex = 0;
    if (lines.isNotEmpty && lines.first.trimLeft().startsWith('{{')) {
      startIndex = 1;
    }

    var endIndex = lines.length;
    while (endIndex > startIndex && lines[endIndex - 1].trim().isEmpty) {
      endIndex--;
    }
    if (endIndex > startIndex && lines[endIndex - 1].trim() == '}}') {
      endIndex--;
    }

    void flush() {
      if (currentKey == null) {
        return;
      }
      values[currentKey!] = currentValue.toString().trim();
      currentKey = null;
      currentValue.clear();
      nestedTemplateDepth = 0;
    }

    for (var lineIndex = startIndex; lineIndex < endIndex; lineIndex++) {
      final line = lines[lineIndex];
      final trimmed = line.trimRight();
      final leftTrim = trimmed.trimLeft();
      final isTopLevelKeyValue =
          currentKey == null ||
          (nestedTemplateDepth == 0 &&
              leftTrim.startsWith('|') &&
              leftTrim.contains('='));
      if (isTopLevelKeyValue &&
          leftTrim.startsWith('|') &&
          leftTrim.contains('=')) {
        flush();
        final eqIndex = leftTrim.indexOf('=');
        final rawKey = leftTrim.substring(1, eqIndex).trim();
        final rawValue = leftTrim.substring(eqIndex + 1).trimRight();
        currentKey = rawKey;
        currentValue.write(rawValue);
        nestedTemplateDepth = _templateDepth(rawValue);
      } else if (currentKey != null) {
        currentValue.writeln();
        currentValue.write(trimmed);
        nestedTemplateDepth += _templateDepth(trimmed);
      }
    }
    flush();
    return values;
  }

  BattleBoxDoc _buildDocFromKeyValues(
    Map<String, String> values, {
    ImportFieldReport? topLevelReport,
  }) {
    final doc = BattleboxSeed(_idGenerator).create();
    var updated = doc.copyWith(customFields: {});
    final custom = <String, String>{};
    final fieldReports = <String, ImportFieldReport>{};
    if (topLevelReport != null) {
      fieldReports[topLevelReport.key] = topLevelReport;
    }

    void setSingle(String label, String? raw) {
      if (raw == null) {
        return;
      }
      updated = _updateSingle(updated, label, raw);
    }

    void setList(String label, String? raw) {
      if (raw == null) {
        return;
      }
      updated = _updateList(updated, label, _parseLines(raw));
    }

    final multiBuckets = <String, Map<int, List<String>>>{};
    int maxIndex = 0;

    values.forEach((key, value) {
      final normalizedKey = key.trim();
      final lowerKey = normalizedKey.toLowerCase();
      switch (lowerKey) {
        case 'conflict':
          updated = updated.copyWith(title: value);
          break;
        case 'partof':
          setSingle('Part of', value);
          break;
        case 'date':
          setList('Date', value);
          break;
        case 'place':
          setList('Location', value);
          break;
        case 'coordinates':
          setSingle('Coordinates', value);
          break;
        case 'result':
        case 'status':
          setSingle('Result', value);
          break;
        case 'territory':
          setSingle('Territorial changes', value);
          break;
        case 'image':
          final extraction = _fieldExtractors.extractMediaImage(value);
          final imageValue = extraction.items.isNotEmpty
              ? extraction.items.first
              : value;
          updated = _updateMedia(updated, lowerKey, imageValue);
          fieldReports[normalizedKey] = _toFieldReport(
            normalizedKey,
            extraction,
          );
          break;
        case 'caption':
        case 'image_size':
        case 'image_upright':
          updated = _updateMedia(updated, lowerKey, value);
          break;
        default:
          const multiSectionKeys = <String>{
            'combatant',
            'commander',
            'units',
            'strength',
            'casualties',
          };
          if (multiSectionKeys.contains(lowerKey)) {
            maxIndex = maxIndex < 1 ? 1 : maxIndex;
            final extraction = _extractForSection(
              sectionKey: lowerKey,
              raw: value,
            );
            final items = _bestEffortItems(extraction.items, value);
            _appendMultiValue(
              buckets: multiBuckets,
              sectionKey: lowerKey,
              columnIndex: 1,
              values: items,
            );
            if (_isTargetedReportSection(lowerKey)) {
              fieldReports[normalizedKey] = _toFieldReport(
                normalizedKey,
                extraction,
              );
            }
            break;
          }

          final match = RegExp(
            r'^(combatant|commander|units|strength|casualties)(\d+)([a-z]+)?$',
          ).firstMatch(lowerKey);
          if (match != null) {
            final sectionKey = match.group(1)!;
            final index = int.tryParse(match.group(2) ?? '') ?? 0;
            if (index > 0) {
              maxIndex = index > maxIndex ? index : maxIndex;
              final extraction = _extractForSection(
                sectionKey: sectionKey,
                raw: value,
              );
              final items = _bestEffortItems(extraction.items, value);
              _appendMultiValue(
                buckets: multiBuckets,
                sectionKey: sectionKey,
                columnIndex: index,
                values: items,
              );
              if (_isTargetedReportSection(sectionKey)) {
                fieldReports[normalizedKey] = _toFieldReport(
                  normalizedKey,
                  extraction,
                );
              }
            }
          } else {
            custom[normalizedKey] = value;
          }
          break;
      }
    });

    if (maxIndex > 0) {
      updated = _updateMultiColumns(updated, maxIndex, multiBuckets);
    }

    return updated.copyWith(
      customFields: custom,
      importReport: WikitextImportReport(fields: fieldReports),
    );
  }

  bool _isTargetedReportSection(String sectionKey) {
    return sectionKey == 'combatant' ||
        sectionKey == 'commander' ||
        sectionKey == 'strength' ||
        sectionKey == 'casualties';
  }

  ImportFieldReport _toFieldReport(
    String key,
    FieldExtractionResult extraction,
  ) {
    return ImportFieldReport(
      key: key,
      status: extraction.status,
      parsedItemCount: extraction.items.length,
      unparsedFragments: extraction.unparsedFragments,
      firstOffendingToken: extraction.firstOffendingToken,
    );
  }

  FieldExtractionResult _extractForSection({
    required String sectionKey,
    required String raw,
  }) {
    switch (sectionKey) {
      case 'combatant':
        return _fieldExtractors.extractCombatant(raw);
      case 'commander':
        return _fieldExtractors.extractCommander(raw);
      case 'strength':
        return _fieldExtractors.extractStrength(raw);
      case 'casualties':
        return _fieldExtractors.extractCasualties(raw);
      default:
        final fallback = _parseLines(raw)
            .map((value) => value.raw.trim())
            .where((value) => value.isNotEmpty)
            .toList();
        return FieldExtractionResult(
          items: fallback,
          unparsedFragments: const [],
          firstOffendingToken: null,
          status: raw.trim().isEmpty
              ? ImportFieldStatus.skipped
              : ImportFieldStatus.parsed,
        );
    }
  }

  List<String> _bestEffortItems(List<String> items, String rawValue) {
    if (items.isNotEmpty) {
      return items;
    }
    final fallback = _parseLines(rawValue)
        .map((value) => value.raw.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (fallback.isNotEmpty) {
      return fallback;
    }
    final trimmed = rawValue.trim();
    return trimmed.isEmpty ? const [] : [trimmed];
  }

  BattleBoxDoc _updateSingle(BattleBoxDoc doc, String label, String value) {
    final sections = doc.sections.map((section) {
      if (section is SingleFieldSection && section.label == label) {
        return section.copyWith(value: RichTextValue(value));
      }
      return section;
    }).toList();
    return doc.copyWith(sections: sections);
  }

  BattleBoxDoc _updateList(
    BattleBoxDoc doc,
    String label,
    List<RichTextValue> items,
  ) {
    final sections = doc.sections.map((section) {
      if (section is ListFieldSection && section.label == label) {
        return section.copyWith(items: items);
      }
      return section;
    }).toList();
    return doc.copyWith(sections: sections);
  }

  BattleBoxDoc _updateMedia(BattleBoxDoc doc, String key, String value) {
    final sections = doc.sections.map((section) {
      if (section is! MediaSection) {
        return section;
      }
      switch (key) {
        case 'image':
          return section.copyWith(imageUrl: value);
        case 'caption':
          return section.copyWith(caption: value);
        case 'image_size':
          return section.copyWith(size: value);
        case 'image_upright':
          return section.copyWith(upright: value);
      }
      return section;
    }).toList();
    return doc.copyWith(sections: sections);
  }

  BattleBoxDoc _updateMultiColumns(
    BattleBoxDoc doc,
    int count,
    Map<String, Map<int, List<String>>> buckets,
  ) {
    final sections = doc.sections.map((section) {
      if (section is! MultiColumnSection) {
        return section;
      }
      final columns = List<ColumnModel>.generate(
        count,
        (index) => ColumnModel(
          id: _idGenerator.newId(),
          label: 'Belligerent ${index + 1}',
        ),
      );
      final cells = List<List<RichTextValue>>.generate(
        count,
        (_) => [const RichTextValue('')],
      );
      final sectionKey = _multiKeyForLabel(section.label);
      final values = buckets[sectionKey] ?? {};
      for (final entry in values.entries) {
        final index = entry.key - 1;
        if (index >= 0 && index < cells.length) {
          cells[index] = _parseLines(entry.value.join('\n'));
        }
      }
      return section.copyWith(columns: columns, cells: cells);
    }).toList();
    return doc.copyWith(sections: sections);
  }

  void _appendMultiValue({
    required Map<String, Map<int, List<String>>> buckets,
    required String sectionKey,
    required int columnIndex,
    required List<String> values,
  }) {
    final byColumn = buckets.putIfAbsent(sectionKey, () => {});
    final existing = byColumn.putIfAbsent(columnIndex, () => []);
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        existing.add(trimmed);
      }
    }
  }

  bool _isSuspiciousBalancedResult(
    String template,
    Map<String, String> values,
  ) {
    // Intentionally counts every pipe as a rough sanity heuristic.
    // Nested templates can inflate this count, but false positives are acceptable
    // because this only decides whether we fall back to the legacy parser.
    final topLevelPipeCount = '|'.allMatches(template).length;
    if (topLevelPipeCount < 4) {
      return false;
    }
    return values.length < 2;
  }

  void _writeSingle(
    StringBuffer buffer,
    BattleBoxDoc doc,
    String label,
    String key,
  ) {
    final section = doc.sections
        .whereType<SingleFieldSection>()
        .where((section) => section.label == label)
        .firstOrNull;
    if (section == null) {
      return;
    }
    _writeKey(buffer, key, section.value?.raw ?? '');
  }

  void _writeList(
    StringBuffer buffer,
    BattleBoxDoc doc,
    String label,
    String key,
  ) {
    final section = doc.sections
        .whereType<ListFieldSection>()
        .where((section) => section.label == label)
        .firstOrNull;
    if (section == null) {
      return;
    }
    final value = section.items.map((item) => item.raw).join('<br />');
    _writeKey(buffer, key, value);
  }

  void _writeMulti(
    StringBuffer buffer,
    BattleBoxDoc doc,
    String label,
    String key,
  ) {
    final section = doc.sections
        .whereType<MultiColumnSection>()
        .where((section) => section.label == label)
        .firstOrNull;
    if (section == null) {
      return;
    }
    for (var i = 0; i < section.columns.length; i++) {
      final value = section.cells[i].map((item) => item.raw).join('<br />');
      _writeKey(buffer, '$key${i + 1}', value);
    }
  }

  void _writeKey(StringBuffer buffer, String key, String value) {
    buffer.writeln('| $key = $value');
  }

  List<RichTextValue> _parseLines(String raw) {
    final normalized = raw
        .replaceAll('<br />', '\n')
        .replaceAll('<br/>', '\n')
        .replaceAll('<br>', '\n')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final parts = _splitTopLevelLines(normalized);
    return parts.map((part) => RichTextValue(part.trim())).toList();
  }

  List<String> _splitTopLevelLines(String input) {
    final parts = <String>[];
    final buffer = StringBuffer();
    var templateDepth = 0;
    var wikiLinkDepth = 0;
    var externalLinkDepth = 0;
    var i = 0;

    while (i < input.length) {
      final char = input[i];

      if (i + 1 < input.length && char == '{' && input[i + 1] == '{') {
        templateDepth++;
        buffer.write('{{');
        i += 2;
        continue;
      }
      if (i + 1 < input.length && char == '}' && input[i + 1] == '}') {
        if (templateDepth > 0) {
          templateDepth--;
        }
        buffer.write('}}');
        i += 2;
        continue;
      }
      if (i + 1 < input.length && char == '[' && input[i + 1] == '[') {
        wikiLinkDepth++;
        buffer.write('[[');
        i += 2;
        continue;
      }
      if (i + 1 < input.length && char == ']' && input[i + 1] == ']') {
        if (wikiLinkDepth > 0) {
          wikiLinkDepth--;
        }
        buffer.write(']]');
        i += 2;
        continue;
      }
      if (char == '[' && (i + 1 >= input.length || input[i + 1] != '[')) {
        if (wikiLinkDepth == 0) {
          externalLinkDepth++;
        }
        buffer.write(char);
        i++;
        continue;
      }
      if (char == ']' && externalLinkDepth > 0 && wikiLinkDepth == 0) {
        externalLinkDepth--;
        buffer.write(char);
        i++;
        continue;
      }

      if (char == '\n' &&
          templateDepth == 0 &&
          wikiLinkDepth == 0 &&
          externalLinkDepth == 0) {
        parts.add(buffer.toString());
        buffer.clear();
        i++;
        continue;
      }

      buffer.write(char);
      i++;
    }

    parts.add(buffer.toString());
    return parts;
  }

  String _multiKeyForLabel(String label) {
    switch (label) {
      case 'Combatants':
        return 'combatant';
      case 'Commanders and leaders':
        return 'commander';
      case 'Units':
        return 'units';
      case 'Strength':
        return 'strength';
      case 'Casualties':
        return 'casualties';
      default:
        return '';
    }
  }

  int _templateDepth(String input) {
    var depth = 0;
    for (var i = 0; i < input.length - 1; i++) {
      final first = input[i];
      final second = input[i + 1];
      if (first == '{' && second == '{') {
        depth++;
        i++;
        continue;
      }
      if (first == '}' && second == '}') {
        depth--;
        i++;
      }
    }
    return depth;
  }
}
