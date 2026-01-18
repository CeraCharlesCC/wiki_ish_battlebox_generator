import '../../domain/entities/battlebox_doc.dart';

/// Port for parsing and exporting battlebox documents.
///
/// This abstraction allows the application layer to work with
/// serialization without depending on specific formats (wikitext, JSON, etc.).
abstract class BattleboxSerializer {
  /// Parses text input into a BattleBoxDoc.
  ///
  /// Returns a seed document if parsing fails.
  BattleBoxDoc parse(String text);

  /// Exports a BattleBoxDoc to text format.
  String export(BattleBoxDoc doc);
}
