import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/usecases/battlebox_editing_usecases.dart';
import '../../application/usecases/export_wikitext.dart';
import '../../application/usecases/import_wikitext.dart';
import '../../domain/entities/battlebox_doc.dart';

/// Riverpod notifier that exposes battlebox editing actions to the UI.
class BattleboxEditorNotifier extends StateNotifier<BattleBoxDoc> {
  final BattleboxEditingUseCases _editing;
  final ImportWikitext _importWikitext;
  final ExportWikitext _exportWikitext;

  BattleboxEditorNotifier({
    required BattleboxEditingUseCases editing,
    required ImportWikitext importWikitext,
    required ExportWikitext exportWikitext,
    required BattleBoxDoc initialDoc,
  })  : _editing = editing,
        _importWikitext = importWikitext,
        _exportWikitext = exportWikitext,
        super(initialDoc);

  void importWikitext(String text) {
    final parsed = _importWikitext(text);
    state = _editing.replaceDoc(state, parsed);
  }

  String exportWikitext() {
    return _exportWikitext(state);
  }

  void replaceDoc(BattleBoxDoc doc) {
    state = _editing.replaceDoc(state, doc);
  }

  void setTitle(String value) {
    state = _editing.setTitle(state, value);
  }

  void setSingleField(String sectionId, String value) {
    state = _editing.setSingleField(state, sectionId, value);
  }

  void clearSingleField(String sectionId) {
    state = _editing.clearSingleField(state, sectionId);
  }

  void addListItem(String sectionId) {
    state = _editing.addListItem(state, sectionId);
  }

  void updateListItem(String sectionId, int index, String value) {
    state = _editing.updateListItem(state, sectionId, index, value);
  }

  void deleteListItem(String sectionId, int index) {
    state = _editing.deleteListItem(state, sectionId, index);
  }

  void updateMultiColumnCell(String sectionId, int columnIndex, String value) {
    state =
        _editing.updateMultiColumnCell(state, sectionId, columnIndex, value);
  }

  void addBelligerentColumn() {
    state = _editing.addBelligerentColumn(state);
  }

  void deleteBelligerentColumn(int index) {
    state = _editing.deleteBelligerentColumn(state, index);
  }

  void setMedia({
    String? imageUrl,
    String? caption,
    String? size,
    String? upright,
  }) {
    state = _editing.setMedia(
      state,
      imageUrl: imageUrl,
      caption: caption,
      size: size,
      upright: upright,
    );
  }
}
