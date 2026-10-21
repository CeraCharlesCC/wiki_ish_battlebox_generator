import 'package:web/web.dart' as web;

import '../../application/ports/editor_draft_storage.dart';

/// Drafts stay in this browser only; no server account or upload is involved.
class BrowserEditorDraftStorage implements EditorDraftStorage {
  static const String storageKey = 'wiki_ish_battlebox_editor_draft_v1';

  @override
  String? read() => web.window.localStorage.getItem(storageKey);

  @override
  void write(String json) => web.window.localStorage.setItem(storageKey, json);

  @override
  void clear() => web.window.localStorage.removeItem(storageKey);
}

EditorDraftStorage createEditorDraftStorage() => BrowserEditorDraftStorage();
