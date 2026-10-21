/// Persistent storage for the last local editor draft.
///
/// In the web application this is backed by browser localStorage. A separate
/// implementation can be injected in tests or for other platforms.
abstract class EditorDraftStorage {
  String? read();
  void write(String json);
  void clear();
}
