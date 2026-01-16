import 'package:flutter/foundation.dart';

enum SectionKind {
  singleField,
  listField,
  multiColumn,
  media,
}

@immutable
class RichTextValue {
  final String raw;

  const RichTextValue(this.raw);

  bool get isEmpty => raw.trim().isEmpty;

  Map<String, dynamic> toJson() => {'raw': raw};

  static RichTextValue fromJson(Map<String, dynamic> json) {
    return RichTextValue(json['raw'] as String? ?? '');
  }
}

@immutable
abstract class SectionModel {
  final String id;
  final String label;
  final SectionKind kind;
  final bool isOptional;
  final bool isVisible;

  const SectionModel({
    required this.id,
    required this.label,
    required this.kind,
    this.isOptional = false,
    this.isVisible = true,
  });
}

@immutable
class SingleFieldSection extends SectionModel {
  final RichTextValue? value;

  const SingleFieldSection({
    required super.id,
    required super.label,
    this.value,
    super.isOptional,
    super.isVisible,
  }) : super(kind: SectionKind.singleField);

  SingleFieldSection copyWith({
    RichTextValue? value,
    bool? isVisible,
    String? label,
  }) {
    return SingleFieldSection(
      id: id,
      label: label ?? this.label,
      value: value,
      isOptional: isOptional,
      isVisible: isVisible ?? this.isVisible,
    );
  }
}

@immutable
class ListFieldSection extends SectionModel {
  final List<RichTextValue> items;

  const ListFieldSection({
    required super.id,
    required super.label,
    required this.items,
    super.isOptional,
    super.isVisible,
  }) : super(kind: SectionKind.listField);

  ListFieldSection copyWith({
    List<RichTextValue>? items,
    bool? isVisible,
    String? label,
  }) {
    return ListFieldSection(
      id: id,
      label: label ?? this.label,
      items: items ?? this.items,
      isOptional: isOptional,
      isVisible: isVisible ?? this.isVisible,
    );
  }
}

@immutable
class ColumnModel {
  final String id;
  final String label;

  const ColumnModel({required this.id, required this.label});
}

@immutable
class MultiColumnSection extends SectionModel {
  final List<ColumnModel> columns;
  final List<List<RichTextValue>> cells;

  const MultiColumnSection({
    required super.id,
    required super.label,
    required this.columns,
    required this.cells,
    super.isOptional,
    super.isVisible,
  }) : super(kind: SectionKind.multiColumn);

  MultiColumnSection copyWith({
    List<ColumnModel>? columns,
    List<List<RichTextValue>>? cells,
    bool? isVisible,
    String? label,
  }) {
    return MultiColumnSection(
      id: id,
      label: label ?? this.label,
      columns: columns ?? this.columns,
      cells: cells ?? this.cells,
      isOptional: isOptional,
      isVisible: isVisible ?? this.isVisible,
    );
  }
}

@immutable
class MediaSection extends SectionModel {
  final String? imageUrl;
  final String? caption;
  final String? size;
  final String? upright;

  const MediaSection({
    required super.id,
    required super.label,
    this.imageUrl,
    this.caption,
    this.size,
    this.upright,
    super.isOptional,
    super.isVisible,
  }) : super(kind: SectionKind.media);

  MediaSection copyWith({
    String? imageUrl,
    String? caption,
    String? size,
    String? upright,
    bool? isVisible,
    String? label,
  }) {
    return MediaSection(
      id: id,
      label: label ?? this.label,
      imageUrl: imageUrl ?? this.imageUrl,
      caption: caption ?? this.caption,
      size: size ?? this.size,
      upright: upright ?? this.upright,
      isOptional: isOptional,
      isVisible: isVisible ?? this.isVisible,
    );
  }
}

@immutable
class BattleBoxDoc {
  final String id;
  final String title;
  final List<SectionModel> sections;
  final String templateName;
  final DateTime? lastEdited;
  final Map<String, String> customFields;

  const BattleBoxDoc({
    required this.id,
    required this.title,
    required this.sections,
    this.templateName = 'Infobox military conflict',
    this.lastEdited,
    this.customFields = const {},
  });

  BattleBoxDoc copyWith({
    String? id,
    String? title,
    List<SectionModel>? sections,
    String? templateName,
    DateTime? lastEdited,
    Map<String, String>? customFields,
  }) {
    return BattleBoxDoc(
      id: id ?? this.id,
      title: title ?? this.title,
      sections: sections ?? this.sections,
      templateName: templateName ?? this.templateName,
      lastEdited: lastEdited ?? this.lastEdited,
      customFields: customFields ?? this.customFields,
    );
  }

  SectionModel? sectionById(String sectionId) {
    for (final section in sections) {
      if (section.id == sectionId) {
        return section;
      }
    }
    return null;
  }

  SectionModel? sectionByLabel(String label) {
    for (final section in sections) {
      if (section.label == label) {
        return section;
      }
    }
    return null;
  }

  static BattleBoxDoc seed() {
    final columns = [
      ColumnModel(id: _newId(), label: 'Belligerent 1'),
      ColumnModel(id: _newId(), label: 'Belligerent 2'),
    ];

    return BattleBoxDoc(
      id: _newId(),
      title: 'Battle of Exampleville',
      sections: [
        const MediaSection(id: 'media', label: 'Media'),
        const SingleFieldSection(id: 'partof', label: 'Part of'),
        const ListFieldSection(
          id: 'date',
          label: 'Date',
          items: [RichTextValue('')],
        ),
        const ListFieldSection(
          id: 'location',
          label: 'Location',
          items: [RichTextValue('')],
        ),
        const SingleFieldSection(id: 'coordinates', label: 'Coordinates'),
        const SingleFieldSection(id: 'result', label: 'Result'),
        const SingleFieldSection(
          id: 'territory',
          label: 'Territorial changes',
        ),
        MultiColumnSection(
          id: 'combatants',
          label: 'Combatants',
          columns: columns,
          cells: _buildEmptyCells(columns.length),
        ),
        MultiColumnSection(
          id: 'commanders',
          label: 'Commanders and leaders',
          columns: columns,
          cells: _buildEmptyCells(columns.length),
        ),
        MultiColumnSection(
          id: 'units',
          label: 'Units',
          columns: columns,
          cells: _buildEmptyCells(columns.length),
        ),
        MultiColumnSection(
          id: 'strength',
          label: 'Strength',
          columns: columns,
          cells: _buildEmptyCells(columns.length),
        ),
        MultiColumnSection(
          id: 'casualties',
          label: 'Casualties',
          columns: columns,
          cells: _buildEmptyCells(columns.length),
        ),
      ],
    );
  }
}

String _newId() {
  return DateTime.now().microsecondsSinceEpoch.toString();
}

List<List<RichTextValue>> _buildEmptyCells(int count) {
  return List<List<RichTextValue>>.generate(
    count,
    (_) => [const RichTextValue('')],
  );
}
