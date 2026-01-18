import 'package:meta/meta.dart';

import 'column_model.dart';
import 'rich_text_value.dart';

enum SectionKind {
  singleField,
  listField,
  multiColumn,
  media,
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
