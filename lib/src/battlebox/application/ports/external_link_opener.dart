/// Port for opening external URLs.
abstract class ExternalLinkOpener {
  /// Opens the given URI in the system browser or appropriate handler.
  ///
  /// Returns true if the URL was successfully launched.
  Future<bool> open(Uri uri);
}
