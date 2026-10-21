/// Resolve image names used in Wikipedia infoboxes to downloadable media URLs.
abstract class WikiImageGateway {
  /// Returns a direct HTTP image URL, or null if an image cannot be found.
  Future<String?> resolveImageUrl(String source, {int widthPx = 760});
}
