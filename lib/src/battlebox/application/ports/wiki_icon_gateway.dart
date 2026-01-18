/// Port for resolving wiki icon macros (e.g., {{flagicon|USA}}) to image URLs.
abstract class WikiIconGateway {
  /// Resolves a flag icon template to an image URL.
  ///
  /// [templateName] The template name (e.g., "flagicon", "flag icon").
  /// [code] The country/entity code (e.g., "USA", "GBR").
  /// [widthPx] The desired width in pixels.
  /// [hostOverride] Optional host override (e.g., "ja" for Japanese Wikipedia).
  ///
  /// Returns the image URL or null if resolution fails.
  Future<String?> resolveFlagIcon({
    required String templateName,
    required String code,
    required int widthPx,
    String? hostOverride,
  });

  /// Disposes any resources held by this gateway.
  void dispose();
}
