import '../../domain/entities/battlebox_doc.dart';
import '../../domain/services/battlebox_editor.dart';

/// Application-layer editing use cases for battlebox documents.
///
/// Thin wrappers around the domain editor to keep orchestration out of UI.
class BattleboxEditingUseCases {
  final BattleboxEditor _editor;

  const BattleboxEditingUseCases({required BattleboxEditor editor})
      : _editor = editor;

  BattleBoxDoc replaceDoc(BattleBoxDoc current, BattleBoxDoc replacement) {
    return _editor.replaceDoc(current, replacement);
  }

  BattleBoxDoc setTitle(BattleBoxDoc doc, String title) {
    return _editor.setTitle(doc, title);
  }

  BattleBoxDoc setSingleField(BattleBoxDoc doc, String sectionId, String value) {
    return _editor.setSingleField(doc, sectionId, value);
  }

  BattleBoxDoc clearSingleField(BattleBoxDoc doc, String sectionId) {
    return _editor.clearSingleField(doc, sectionId);
  }

  BattleBoxDoc addListItem(BattleBoxDoc doc, String sectionId) {
    return _editor.addListItem(doc, sectionId);
  }

  BattleBoxDoc updateListItem(
    BattleBoxDoc doc,
    String sectionId,
    int index,
    String value,
  ) {
    return _editor.updateListItem(doc, sectionId, index, value);
  }

  BattleBoxDoc deleteListItem(
    BattleBoxDoc doc,
    String sectionId,
    int index,
  ) {
    return _editor.deleteListItem(doc, sectionId, index);
  }

  BattleBoxDoc updateMultiColumnCell(
    BattleBoxDoc doc,
    String sectionId,
    int columnIndex,
    String value,
  ) {
    return _editor.updateMultiColumnCell(
      doc,
      sectionId,
      columnIndex,
      value,
    );
  }

  BattleBoxDoc addBelligerentColumn(BattleBoxDoc doc) {
    return _editor.addBelligerentColumn(doc);
  }

  BattleBoxDoc deleteBelligerentColumn(BattleBoxDoc doc, int index) {
    return _editor.deleteBelligerentColumn(doc, index);
  }

  BattleBoxDoc setMedia(
    BattleBoxDoc doc, {
    String? imageUrl,
    String? caption,
    String? size,
    String? upright,
  }) {
    return _editor.setMedia(
      doc,
      imageUrl: imageUrl,
      caption: caption,
      size: size,
      upright: upright,
    );
  }
}
