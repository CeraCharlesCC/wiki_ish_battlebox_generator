import 'package:meta/meta.dart';

/// Model representing a column in multi-column sections.
@immutable
class ColumnModel {
  final String id;
  final String label;

  const ColumnModel({required this.id, required this.label});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColumnModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label;

  @override
  int get hashCode => Object.hash(id, label);

  @override
  String toString() => 'ColumnModel(id: $id, label: $label)';
}
