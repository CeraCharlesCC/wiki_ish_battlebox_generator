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
  /// Do not turn malformed/untrusted input into an unbounded number of widgets.
  static const int maxColumns = 32;
  static const int maxWikitextLength = 1024 * 1024;

  /// Includes the outer infobox; checked before recursive normalization.
  static const int maxTemplateDepth = 64;

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
    if (input.trim().isEmpty) {
      throw const FormatException(
        'Paste an Infobox military conflict template.',
      );
    }
    if (input.length > maxWikitextLength) {
      throw const FormatException('Wikitext exceeds the 1 MiB import limit.');
    }
    final template = _extractTemplate(input);
    if (template == null) {
      throw const FormatException(
        'No complete Infobox military conflict template was found.',
      );
    }

    Map<String, String> keyValues;
    ImportFieldReport? topLevelReport;

    try {
      keyValues = _parseKeyValuesBalanced(template);
      final unparsedParameters = _unparsedTopLevelParameters(template);
      if (unparsedParameters.isNotEmpty && keyValues.length < 2) {
        throw const FormatException(
          'Balanced parser produced too few infobox fields.',
        );
      }
      if (unparsedParameters.isNotEmpty) {
        // Named fields can still be imported safely, but these parameters are
        // not represented in the visual document or its export. Keep their
        // source in the report and disclose the loss regardless of field count.
        topLevelReport = ImportFieldReport(
          key: '__infobox__',
          status: ImportFieldStatus.partial,
          parsedItemCount: keyValues.length,
          unparsedFragments: unparsedParameters,
          firstOffendingToken: 'Unsupported unnamed infobox parameter',
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

    if (!_containsRecognizedFields(keyValues)) {
      throw const FormatException(
        'Infobox contains no recognized, non-empty battlebox fields.',
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
      var image = media.imageUrl ?? '';
      final rawImage = doc.customFields['image'];
      if (rawImage != null) {
        final extracted = _fieldExtractors.extractMediaImage(rawImage);
        if (extracted.items.isNotEmpty && extracted.items.first == image) {
          // No visual edit was made: keep the whole multi-image template.
          image = rawImage;
        }
      }
      _writeKey(buffer, 'image', image);
      _writeKey(buffer, 'caption', media.caption ?? '');
      _writeKey(buffer, 'image_size', media.size ?? '');
      _writeKey(buffer, 'image_upright', media.upright ?? '');
    }

    _writeSingle(buffer, doc, 'Part of', 'partof');
    _writeList(buffer, doc, 'Date', 'date');
    _writeList(buffer, doc, 'Location', 'place');
    _writeSingle(buffer, doc, 'Coordinates', 'coordinates');
    final hasStatus = doc.customFields.containsKey('status');
    final hasResult = doc.customFields.containsKey('result');
    _writeSingle(
      buffer,
      doc,
      'Result',
      hasStatus && !hasResult ? 'status' : 'result',
    );
    _writeSingle(buffer, doc, 'Territorial changes', 'territory');

    _writeMulti(buffer, doc, 'Combatants', 'combatant');
    _writeMulti(buffer, doc, 'Commanders and leaders', 'commander');
    _writeMulti(buffer, doc, 'Units', 'units');
    _writeMulti(buffer, doc, 'Strength', 'strength');
    _writeMulti(buffer, doc, 'Casualties', 'casualties');

    for (final entry in doc.customFields.entries) {
      if (entry.key == 'image' || entry.key == 'result' && hasStatus) {
        // Internal round-trip value, already written from the visual field.
        continue;
      }
      if (entry.key == 'status') {
        // When both result and status were imported, keep the second original
        // field rather than silently merging two distinct meanings.
        if (hasResult) {
          _writeKey(buffer, 'status', entry.value);
        }
        continue;
      }
      _writeKey(buffer, entry.key, entry.value);
    }

    buffer.writeln('}}');
    return buffer.toString();
  }

  String? _extractTemplate(String input) {
    final startIndex = _findInfoboxStart(input);
    if (startIndex == null) {
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
        if (depth > maxTemplateDepth) {
          throw const FormatException(
            'Wikitext exceeds the template nesting limit of $maxTemplateDepth.',
          );
        }
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

  int? _findInfoboxStart(String input) {
    final header = RegExp(
      r'\{\{\s*Infobox[ _]+military[ _]+conflict(?=\s*(?:\||\}\}|<!--))',
      caseSensitive: false,
    );
    final refStart = RegExp(r'<ref\b', caseSensitive: false);
    final lower = input.toLowerCase();
    var index = 0;

    while (index < input.length) {
      if (input.startsWith('<!--', index)) {
        final end = input.indexOf('-->', index + 4);
        if (end < 0) return null;
        index = end + 3;
        continue;
      }
      if (refStart.matchAsPrefix(input, index) != null) {
        final tagEnd = input.indexOf('>', index + 4);
        if (tagEnd < 0) return null;
        final selfClosing = input
            .substring(index, tagEnd + 1)
            .trimRight()
            .endsWith('/>');
        if (selfClosing) {
          index = tagEnd + 1;
          continue;
        }
        final end = lower.indexOf('</ref>', tagEnd + 1);
        if (end < 0) return null;
        index = end + 6;
        continue;
      }
      if (header.matchAsPrefix(input, index) != null) {
        return index;
      }
      index++;
    }
    return null;
  }

  bool _containsRecognizedFields(Map<String, String> fields) {
    const known = <String>{
      'conflict',
      'partof',
      'date',
      'place',
      'coordinates',
      'result',
      'status',
      'territory',
      'image',
      'caption',
      'image_size',
      'image_upright',
      'combatant',
      'commander',
      'units',
      'strength',
      'casualties',
    };
    final numbered = RegExp(
      r'^(combatant|commander|units|strength|casualties)0*[1-9]\d*[a-z]*$',
    );
    return fields.entries.any((entry) {
      final key = entry.key.trim().toLowerCase();
      return entry.value.trim().isNotEmpty &&
          (known.contains(key) || numbered.hasMatch(key));
    });
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
    var updated = doc.copyWith(title: '', customFields: {});
    final custom = <String, String>{};
    final fieldReports = <String, ImportFieldReport>{};
    final hasResultKey = values.keys.any(
      (key) => key.trim().toLowerCase() == 'result',
    );
    final hasStatusKey = values.keys.any(
      (key) => key.trim().toLowerCase() == 'status',
    );
    if (topLevelReport != null) {
      fieldReports[topLevelReport.key] = topLevelReport;
    }

    void setSingle(String label, String? raw) {
      if (raw == null) {
        return;
      }
      updated = _updateSingle(updated, label, raw);
    }

    void setList(String label, String key, String? raw) {
      if (raw == null) {
        return;
      }
      final extraction = _fieldExtractors.extractGenericList(raw);
      updated = _updateList(
        updated,
        label,
        extraction.items.isEmpty
            ? [const RichTextValue('')]
            : extraction.items.map((item) => RichTextValue(item)).toList(),
      );
      if (extraction.status == ImportFieldStatus.partial ||
          extraction.status == ImportFieldStatus.failed) {
        fieldReports[key] = _toFieldReport(key, extraction);
      }
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
          setList('Date', normalizedKey, value);
          break;
        case 'place':
          setList('Location', normalizedKey, value);
          break;
        case 'coordinates':
          setSingle('Coordinates', value);
          break;
        case 'result':
          setSingle('Result', value);
          if (hasStatusKey) {
            custom['result'] = value;
          }
          break;
        case 'status':
          if (!hasResultKey) {
            setSingle('Result', value);
          }
          custom['status'] = value;
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
          if (extraction.items.isNotEmpty &&
              RegExp(
                r'^\s*\{\{\s*multiple\s+image\b',
                caseSensitive: false,
              ).hasMatch(value)) {
            custom['image'] = value;
          }
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
            final index = int.tryParse(match.group(2) ?? '');
            if (index == null || index > maxColumns) {
              final shortKey = normalizedKey.length <= 72
                  ? normalizedKey
                  : '${normalizedKey.substring(0, 72)}...';
              throw FormatException(
                'Battlebox supports at most $maxColumns columns '
                '(invalid $shortKey).',
              );
            }
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
            } else {
              // Non-positive indices have no corresponding visual column.
              custom[normalizedKey] = value;
              fieldReports[normalizedKey] = ImportFieldReport(
                key: normalizedKey,
                status: ImportFieldStatus.partial,
                parsedItemCount: 0,
                unparsedFragments: [value],
                firstOffendingToken: 'column index',
              );
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
        return _fieldExtractors.extractGenericList(raw);
    }
  }

  List<String> _bestEffortItems(List<String> items, String rawValue) {
    if (items.isNotEmpty) {
      return items;
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
          // Entries are already split safely by the field extractor. Joining
          // and reparsing here could split <br> inside <ref> and destroy it.
          cells[index] = entry.value
              .map((value) => RichTextValue(value))
              .toList();
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

  List<String> _unparsedTopLevelParameters(String template) {
    // Counting literal pipes misclassifies valid single-field infoboxes with
    // nested {{Bulletlist|...}} values. Inspect actual top-level parameters.
    final inner = template.substring(2, template.length - 2);
    final parts = _balancedScanner.splitTopLevel(
      inner,
      isSeparator: (state, index) => state.isTopLevel && inner[index] == '|',
    );
    return parts
        .skip(1)
        .where((part) {
          if (part.trim().isEmpty) return false;
          final equals = _balancedScanner.indexOfTopLevelEquals(part);
          return equals <= 0 || part.substring(0, equals).trim().isEmpty;
        })
        .map((part) => part.trim())
        .toList();
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
