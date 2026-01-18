import 'package:meta/meta.dart';

/// A wrapper for raw wikitext strings that may contain markup.
@immutable
class RichTextValue {
  final String raw;

  const RichTextValue(this.raw);

  bool get isEmpty => raw.trim().isEmpty;

  Map<String, dynamic> toJson() => {'raw': raw};

  static RichTextValue fromJson(Map<String, dynamic> json) {
    return RichTextValue(json['raw'] as String? ?? '');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RichTextValue &&
          runtimeType == other.runtimeType &&
          raw == other.raw;

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() => 'RichTextValue($raw)';
}
