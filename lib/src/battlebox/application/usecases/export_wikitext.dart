import '../ports/battlebox_serializer.dart';
import '../../domain/entities/battlebox_doc.dart';

/// Use case for exporting a battlebox document to wikitext.
class ExportWikitext {
  final BattleboxSerializer _serializer;

  const ExportWikitext(this._serializer);

  String call(BattleBoxDoc doc) {
    return _serializer.export(doc);
  }
}
