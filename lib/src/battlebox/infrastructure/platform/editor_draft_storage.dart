import '../../application/ports/editor_draft_storage.dart';
import 'editor_draft_storage_stub.dart'
    if (dart.library.js_interop) 'editor_draft_storage_web.dart'
    as platform;

EditorDraftStorage createEditorDraftStorage() =>
    platform.createEditorDraftStorage();
