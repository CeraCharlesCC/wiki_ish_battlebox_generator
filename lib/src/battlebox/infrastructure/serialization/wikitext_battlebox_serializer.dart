import '../../../core/id_generator.dart';
import '../../application/ports/battlebox_serializer.dart';
import '../../domain/entities/battlebox_doc.dart';
import '../../domain/entities/column_model.dart';
import '../../domain/entities/rich_text_value.dart';
import '../../domain/entities/sections.dart';
import '../../domain/services/battlebox_seed.dart';

/// Wikitext implementation of BattleboxSerializer.
///
/// Parses and exports battlebox documents in Wikipedia template format.
class WikitextBattleboxSerializer implements BattleboxSerializer {
  final IdGenerator _idGenerator;

  WikitextBattleboxSerializer({IdGenerator? idGenerator})
      : _idGenerator = idGenerator ?? const TimestampIdGenerator();

  @override
  BattleBoxDoc parse(String input) {
    final template = _extractTemplate(input);
    if (template == null) {
      return BattleboxSeed(_idGenerator).create();
    }
    final keyValues = _parseKeyValues(template);
    return _buildDocFromKeyValues(keyValues);
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
    for (var i = startIndex; i < input.length - 1; i++) {
      final slice = input.substring(i, i + 2);
      if (slice == '{{') {
        depth++;
      } else if (slice == '}}') {
        depth--;
        if (depth == 0) {
          return input.substring(startIndex, i + 2);
        }
      }
    }
    return null;
  }

  Map<String, String> _parseKeyValues(String template) {
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
      if (isTopLevelKeyValue && leftTrim.startsWith('|') && leftTrim.contains('=')) {
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

  BattleBoxDoc _buildDocFromKeyValues(Map<String, String> values) {
    final doc = BattleboxSeed(_idGenerator).create();
    var updated = doc.copyWith(customFields: {});
    final custom = <String, String>{};

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
        case 'caption':
        case 'image_size':
        case 'image_upright':
          updated = _updateMedia(updated, lowerKey, value);
          break;
        default:
          const multiSectionKeys = {
            'combatant',
            'commander',
            'units',
            'strength',
            'casualties',
          };
          if (multiSectionKeys.contains(lowerKey)) {
            maxIndex = maxIndex < 1 ? 1 : maxIndex;
            _appendMultiValue(
              buckets: multiBuckets,
              sectionKey: lowerKey,
              columnIndex: 1,
              value: value,
            );
            break;
          }

          final match = RegExp(r'^(combatant|commander|units|strength|casualties)(\d+)([a-z]+)?$')
              .firstMatch(lowerKey);
          if (match != null) {
            final sectionKey = match.group(1)!;
            final index = int.tryParse(match.group(2) ?? '') ?? 0;
            if (index > 0) {
              maxIndex = index > maxIndex ? index : maxIndex;
              _appendMultiValue(
                buckets: multiBuckets,
                sectionKey: sectionKey,
                columnIndex: index,
                value: value,
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

    return updated.copyWith(customFields: custom);
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
    required String value,
  }) {
    final byColumn = buckets.putIfAbsent(sectionKey, () => {});
    final values = byColumn.putIfAbsent(columnIndex, () => []);
    values.add(value);
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
    final normalized = raw.replaceAll('<br>', '\n').replaceAll('<br />', '\n');
    final parts = normalized.split('\n');
    return parts.map((part) => RichTextValue(part.trim())).toList();
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
