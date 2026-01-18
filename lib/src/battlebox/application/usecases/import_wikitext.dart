import '../ports/battlebox_serializer.dart';
import '../../domain/entities/battlebox_doc.dart';

/// Use case for importing wikitext into a battlebox document.
class ImportWikitext {
  final BattleboxSerializer _serializer;

  const ImportWikitext(this._serializer);

  BattleBoxDoc call(String text) {
    return _serializer.parse(text);
  }
}
