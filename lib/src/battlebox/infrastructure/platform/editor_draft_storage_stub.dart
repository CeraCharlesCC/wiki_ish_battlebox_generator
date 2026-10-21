import '../../application/ports/editor_draft_storage.dart';

/// In-memory fallback outside the web target (use injectable storage on native).
class MemoryEditorDraftStorage implements EditorDraftStorage {
  String? _draft;

  @override
  String? read() => _draft;

  @override
  void write(String json) => _draft = json;

  @override
  void clear() => _draft = null;
}

EditorDraftStorage createEditorDraftStorage() => MemoryEditorDraftStorage();
