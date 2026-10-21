import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/usecases/battlebox_editing_usecases.dart';
import '../../application/usecases/export_wikitext.dart';
import '../../application/usecases/import_wikitext.dart';
import '../../domain/entities/battlebox_doc.dart';

/// Riverpod notifier that exposes battlebox editing actions to the UI.
class BattleboxEditorNotifier extends StateNotifier<BattleBoxDoc> {
  static const int maxUndoSteps = 100;

  final BattleboxEditingUseCases _editing;
  final ImportWikitext _importWikitext;
  final ExportWikitext _exportWikitext;
  final List<BattleBoxDoc> _undoStack = [];
  final List<BattleBoxDoc> _redoStack = [];

  BattleboxEditorNotifier({
    required BattleboxEditingUseCases editing,
    required ImportWikitext importWikitext,
    required ExportWikitext exportWikitext,
    required BattleBoxDoc initialDoc,
  }) : _editing = editing,
       _importWikitext = importWikitext,
       _exportWikitext = exportWikitext,
       super(initialDoc);

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Keep the previous document (and undo history) if parsing throws.
  void importWikitext(String text) {
    final parsed = _importWikitext(text);
    _commit(_editing.replaceDoc(state, parsed));
  }

  /// Load a saved draft as the initial state, not an undoable user edit.
  void restoreWikitext(String text) {
    final parsed = _importWikitext(text);
    final restored = _editing.replaceDoc(state, parsed);
    _undoStack.clear();
    _redoStack.clear();
    state = restored;
  }

  String exportWikitext() {
    return _exportWikitext(state);
  }

  void replaceDoc(BattleBoxDoc doc) {
    _commit(_editing.replaceDoc(state, doc));
  }

  void undo() {
    if (!canUndo) return;
    _redoStack.add(state);
    state = _undoStack.removeLast();
  }

  void redo() {
    if (!canRedo) return;
    _undoStack.add(state);
    state = _redoStack.removeLast();
  }

  void _commit(BattleBoxDoc next) {
    if (identical(next, state)) return;
    _undoStack.add(state);
    if (_undoStack.length > maxUndoSteps) _undoStack.removeAt(0);
    _redoStack.clear();
    state = next;
  }

  void setTitle(String value) {
    if (state.title == value) return;
    _commit(_editing.setTitle(state, value));
  }

  void setSingleField(String sectionId, String value) {
    _commit(_editing.setSingleField(state, sectionId, value));
  }

  void clearSingleField(String sectionId) {
    _commit(_editing.clearSingleField(state, sectionId));
  }

  void addListItem(String sectionId) {
    _commit(_editing.addListItem(state, sectionId));
  }

  void updateListItem(String sectionId, int index, String value) {
    _commit(_editing.updateListItem(state, sectionId, index, value));
  }

  void deleteListItem(String sectionId, int index) {
    _commit(_editing.deleteListItem(state, sectionId, index));
  }

  void updateMultiColumnCell(String sectionId, int columnIndex, String value) {
    _commit(
      _editing.updateMultiColumnCell(state, sectionId, columnIndex, value),
    );
  }

  void addBelligerentColumn() {
    _commit(_editing.addBelligerentColumn(state));
  }

  void deleteBelligerentColumn(int index) {
    _commit(_editing.deleteBelligerentColumn(state, index));
  }

  void setMedia({
    String? imageUrl,
    String? caption,
    String? size,
    String? upright,
  }) {
    _commit(
      _editing.setMedia(
        state,
        imageUrl: imageUrl,
        caption: caption,
        size: size,
        upright: upright,
      ),
    );
  }
}
