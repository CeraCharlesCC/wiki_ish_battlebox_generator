/// Result of resolving a wiki link to a URL.
class ResolvedWikiLink {
  /// The canonical URL for the page (preferred).
  final String? canonicalUrl;

  /// The full URL for the page.
  final String fullUrl;

  /// The wiki host (e.g., "en.wikipedia.org").
  final String wikiHost;

  /// The language code (e.g., "en").
  final String langCode;

  /// The page ID (if available).
  final int? pageId;

  /// The resolved title (post-redirect normalized).
  final String? resolvedTitle;

  /// Whether the resolution followed a redirect.
  final bool wasRedirect;

  const ResolvedWikiLink({
    this.canonicalUrl,
    required this.fullUrl,
    required this.wikiHost,
    required this.langCode,
    this.pageId,
    this.resolvedTitle,
    this.wasRedirect = false,
  });

  /// The best URL to use (canonical if available, otherwise full).
  String get url => canonicalUrl ?? fullUrl;
}

/// Port for resolving wiki link targets to Wikipedia URLs.
abstract class WikiLinkGateway {
  /// Resolves a wiki link target to a Wikipedia URL.
  ///
  /// [rawTarget] The target page (e.g., "Battle of Normandy").
  /// [fragment] Optional section anchor.
  /// [forcedLang] Override language detection (e.g., from `:ja:Title`).
  /// [defaultLang] Fallback language (default: "en").
  ///
  /// Returns the resolved link or null if resolution fails.
  Future<ResolvedWikiLink?> resolve({
    required String rawTarget,
    String? fragment,
    String? forcedLang,
    String defaultLang = 'en',
  });

  /// Builds a naive URL without probing (for quick link generation).
  String buildNaiveUrl({
    required String rawTarget,
    String? fragment,
    String? langPrefix,
    String defaultLang = 'en',
  });

  /// Fetches the SiteMatrix (list of all Wikipedia language editions).
  Future<Map<String, String>> fetchSiteMatrix();

  /// Disposes any resources held by this gateway.
  void dispose();
}
