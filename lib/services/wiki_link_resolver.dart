import 'dart:convert';

import 'package:http/http.dart' as http;

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

/// Cache entry for resolved wiki links.
class _ResolveCacheEntry {
  final ResolvedWikiLink? result;
  final DateTime timestamp;

  const _ResolveCacheEntry(this.result, this.timestamp);

  bool isExpired(Duration ttl) =>
      DateTime.now().difference(timestamp) > ttl;
}

/// Cache entry for SiteMatrix data.
class _SiteMatrixCacheEntry {
  final Map<String, String> langToHost;
  final DateTime timestamp;

  const _SiteMatrixCacheEntry(this.langToHost, this.timestamp);

  bool isExpired(Duration ttl) =>
      DateTime.now().difference(timestamp) > ttl;
}

/// Resolves wiki link targets to actual Wikipedia URLs.
///
/// Features:
/// - Fetches and caches Wikipedia language editions via SiteMatrix API
/// - Probes candidate languages for page existence
/// - Uses script heuristics to prioritize language candidates
/// - Caches resolved URLs to minimize API calls
class WikiLinkResolver {
  WikiLinkResolver({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _userAgent =
      'BattleboxGenerator/0.1 (contact: https://github.com/ceracharlescc/)';

  // Cache TTLs
  static const Duration _siteMatrixTtl = Duration(days: 7);
  static const Duration _resolveTtl = Duration(days: 30);
  static const Duration _negativeCacheTtl = Duration(days: 1);

  // Maximum number of language candidates to probe
  static const int _maxProbeCount = 5;

  // Caches
  _SiteMatrixCacheEntry? _siteMatrixCache;
  final Map<String, _ResolveCacheEntry> _resolveCache = {};
  final Map<String, Future<ResolvedWikiLink?>> _pending = {};

  /// Resolves a wiki link target to a Wikipedia URL.
  ///
  /// [rawTarget] is the target page (e.g., "ジュノー・ビーチの戦い").
  /// [fragment] is an optional section anchor.
  /// [forcedLang] overrides language detection (e.g., from `:ja:Title`).
  /// [defaultLang] is the fallback language (default: "en").
  Future<ResolvedWikiLink?> resolve({
    required String rawTarget,
    String? fragment,
    String? forcedLang,
    String defaultLang = 'en',
  }) async {
    if (rawTarget.trim().isEmpty) {
      return null;
    }

    final cacheKey = _makeCacheKey(rawTarget, forcedLang);

    // Check cache first
    final cached = _resolveCache[cacheKey];
    if (cached != null) {
      final ttl = cached.result == null ? _negativeCacheTtl : _resolveTtl;
      if (!cached.isExpired(ttl)) {
        return _addFragment(cached.result, fragment);
      }
    }

    // Check for pending request
    final existing = _pending[cacheKey];
    if (existing != null) {
      final result = await existing;
      return _addFragment(result, fragment);
    }

    // Start new resolution
    final future = _resolveInternal(
      rawTarget: rawTarget,
      forcedLang: forcedLang,
      defaultLang: defaultLang,
    );
    _pending[cacheKey] = future;

    try {
      final result = await future;
      _resolveCache[cacheKey] = _ResolveCacheEntry(result, DateTime.now());
      return _addFragment(result, fragment);
    } finally {
      _pending.remove(cacheKey);
    }
  }

  /// Builds a naive URL without probing (for Milestone 1).
  ///
  /// This creates a URL that may or may not exist, useful for
  /// quick link generation before full resolution is implemented.
  String buildNaiveUrl({
    required String rawTarget,
    String? fragment,
    String? langPrefix,
    String defaultLang = 'en',
  }) {
    final lang = langPrefix ?? _detectPrimaryLanguage(rawTarget) ?? defaultLang;
    final host = '$lang.wikipedia.org';
    final encodedTitle = Uri.encodeComponent(rawTarget.replaceAll(' ', '_'));
    var url = 'https://$host/wiki/$encodedTitle';
    if (fragment != null && fragment.isNotEmpty) {
      url += '#${Uri.encodeComponent(fragment.replaceAll(' ', '_'))}';
    }
    return url;
  }

  /// Fetches the SiteMatrix (list of all Wikipedia language editions).
  Future<Map<String, String>> fetchSiteMatrix() async {
    // Check cache
    if (_siteMatrixCache != null && !_siteMatrixCache!.isExpired(_siteMatrixTtl)) {
      return _siteMatrixCache!.langToHost;
    }

    final uri = Uri.https('meta.wikimedia.org', '/w/api.php', {
      'action': 'sitematrix',
      'format': 'json',
      'formatversion': '2',
      'origin': '*',
      'smtype': 'language',
      'smlangprop': 'code|site',
      'smsiteprop': 'url|code',
    });

    try {
      final resp = await _client.get(
        uri,
        headers: {'Api-User-Agent': _userAgent},
      );

      if (resp.statusCode != 200) {
        return _getFallbackSiteMatrix();
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        return _getFallbackSiteMatrix();
      }

      final sitematrix = decoded['sitematrix'];
      if (sitematrix is! Map<String, dynamic>) {
        return _getFallbackSiteMatrix();
      }

      final langToHost = <String, String>{};

      // SiteMatrix returns numbered keys for language entries
      for (final entry in sitematrix.entries) {
        if (entry.key == 'count' || entry.key == 'specials') continue;

        final langData = entry.value;
        if (langData is! Map<String, dynamic>) continue;

        final code = langData['code'];
        if (code is! String) continue;

        final sites = langData['site'];
        if (sites is! List) continue;

        // Find the Wikipedia site (code == "wiki")
        for (final site in sites) {
          if (site is! Map<String, dynamic>) continue;
          if (site['code'] == 'wiki') {
            final url = site['url'];
            if (url is String) {
              // Extract host from URL (e.g., "https://en.wikipedia.org" -> "en.wikipedia.org")
              final host = url.replaceFirst(RegExp(r'^https?://'), '');
              langToHost[code] = host;
              break;
            }
          }
        }
      }

      _siteMatrixCache = _SiteMatrixCacheEntry(langToHost, DateTime.now());
      return langToHost;
    } catch (_) {
      return _getFallbackSiteMatrix();
    }
  }

  /// Returns a fallback SiteMatrix with common languages.
  Map<String, String> _getFallbackSiteMatrix() {
    return const {
      'en': 'en.wikipedia.org',
      'ja': 'ja.wikipedia.org',
      'de': 'de.wikipedia.org',
      'fr': 'fr.wikipedia.org',
      'es': 'es.wikipedia.org',
      'it': 'it.wikipedia.org',
      'pt': 'pt.wikipedia.org',
      'ru': 'ru.wikipedia.org',
      'zh': 'zh.wikipedia.org',
      'ko': 'ko.wikipedia.org',
      'ar': 'ar.wikipedia.org',
      'nl': 'nl.wikipedia.org',
      'pl': 'pl.wikipedia.org',
      'uk': 'uk.wikipedia.org',
      'vi': 'vi.wikipedia.org',
    };
  }

  /// Internal resolution logic.
  Future<ResolvedWikiLink?> _resolveInternal({
    required String rawTarget,
    String? forcedLang,
    required String defaultLang,
  }) async {
    final siteMatrix = await fetchSiteMatrix();

    // Build candidate list
    final candidates = <String>[];

    if (forcedLang != null && siteMatrix.containsKey(forcedLang)) {
      // Forced language - only try this one
      candidates.add(forcedLang);
    } else {
      // Use heuristics to determine candidate languages
      final detected = _detectLanguageCandidates(rawTarget, defaultLang);
      for (final lang in detected) {
        if (siteMatrix.containsKey(lang)) {
          candidates.add(lang);
        }
        if (candidates.length >= _maxProbeCount) break;
      }
    }

    // Probe candidates
    for (final lang in candidates) {
      final host = siteMatrix[lang]!;
      final result = await _probeTitle(rawTarget, host, lang);
      if (result != null) {
        return result;
      }
    }

    return null;
  }

  /// Probes a specific wiki for the given title.
  Future<ResolvedWikiLink?> _probeTitle(
    String title,
    String host,
    String langCode,
  ) async {
    final uri = Uri.https(host, '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'formatversion': '2',
      'origin': '*',
      'titles': title,
      'prop': 'info',
      'inprop': 'url',
      'redirects': '1',
    });

    try {
      final resp = await _client.get(
        uri,
        headers: {'Api-User-Agent': _userAgent},
      );

      if (resp.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final query = decoded['query'];
      if (query is! Map<String, dynamic>) {
        return null;
      }

      // Check for redirects
      final redirects = query['redirects'];
      final wasRedirect = redirects is List && redirects.isNotEmpty;

      final pages = query['pages'];
      if (pages is! List || pages.isEmpty) {
        return null;
      }

      final page = pages.first;
      if (page is! Map<String, dynamic>) {
        return null;
      }

      // Check if page is missing
      if (page['missing'] == true) {
        return null;
      }

      final pageId = page['pageid'];
      final canonicalUrl = page['canonicalurl'];
      final fullUrl = page['fullurl'];
      final resolvedTitle = page['title'];

      if (fullUrl is! String) {
        return null;
      }

      return ResolvedWikiLink(
        canonicalUrl: canonicalUrl is String ? canonicalUrl : null,
        fullUrl: fullUrl,
        wikiHost: host,
        langCode: langCode,
        pageId: pageId is int ? pageId : null,
        resolvedTitle: resolvedTitle is String ? resolvedTitle : null,
        wasRedirect: wasRedirect,
      );
    } catch (_) {
      return null;
    }
  }

  /// Detects the primary language based on script analysis.
  String? _detectPrimaryLanguage(String text) {
    if (text.isEmpty) return null;

    var kanaKanjiCount = 0;
    var hangulCount = 0;
    var cyrillicCount = 0;
    var arabicCount = 0;
    var hanCount = 0;

    for (final rune in text.runes) {
      if (_isKana(rune) || _isKanji(rune)) {
        kanaKanjiCount++;
        if (_isKanji(rune)) hanCount++;
      } else if (_isHangul(rune)) {
        hangulCount++;
      } else if (_isCyrillic(rune)) {
        cyrillicCount++;
      } else if (_isArabic(rune)) {
        arabicCount++;
      } else if (_isHan(rune)) {
        hanCount++;
      }
    }

    final total = text.runes.length;
    if (total == 0) return null;

    // Kana/Kanji heavy -> Japanese
    if (kanaKanjiCount > total * 0.3) {
      return 'ja';
    }

    // Hangul -> Korean
    if (hangulCount > total * 0.3) {
      return 'ko';
    }

    // Cyrillic -> Russian (primary), could also be Ukrainian, etc.
    if (cyrillicCount > total * 0.3) {
      return 'ru';
    }

    // Arabic script -> Arabic (primary)
    if (arabicCount > total * 0.3) {
      return 'ar';
    }

    // Han-only (no kana) -> Chinese
    if (hanCount > total * 0.3 && kanaKanjiCount == hanCount) {
      return 'zh';
    }

    // Latin script or mixed -> null (use default)
    return null;
  }

  /// Returns a list of language candidates based on script heuristics.
  List<String> _detectLanguageCandidates(String text, String defaultLang) {
    final candidates = <String>[];

    final primary = _detectPrimaryLanguage(text);
    if (primary != null) {
      candidates.add(primary);

      // Add related languages
      switch (primary) {
        case 'ja':
          candidates.addAll(['zh', 'ko']);
        case 'zh':
          candidates.addAll(['ja', 'ko']);
        case 'ko':
          candidates.addAll(['ja', 'zh']);
        case 'ru':
          candidates.addAll(['uk', 'bg', 'sr']);
        case 'ar':
          candidates.addAll(['fa', 'ur']);
      }
    }

    // Add default language if not already present
    if (!candidates.contains(defaultLang)) {
      candidates.add(defaultLang);
    }

    // Add common Latin-script languages as fallback
    if (primary == null) {
      candidates.addAll(['es', 'fr', 'de', 'pt', 'it']);
    }

    return candidates;
  }

  String _makeCacheKey(String rawTarget, String? forcedLang) {
    return forcedLang != null ? '$forcedLang:$rawTarget' : rawTarget;
  }

  ResolvedWikiLink? _addFragment(ResolvedWikiLink? result, String? fragment) {
    if (result == null || fragment == null || fragment.isEmpty) {
      return result;
    }

    final encodedFragment = Uri.encodeComponent(fragment.replaceAll(' ', '_'));
    return ResolvedWikiLink(
      canonicalUrl: result.canonicalUrl != null
          ? '${result.canonicalUrl}#$encodedFragment'
          : null,
      fullUrl: '${result.fullUrl}#$encodedFragment',
      wikiHost: result.wikiHost,
      langCode: result.langCode,
      pageId: result.pageId,
      resolvedTitle: result.resolvedTitle,
      wasRedirect: result.wasRedirect,
    );
  }

  // Unicode range checks
  bool _isKana(int rune) =>
      (rune >= 0x3040 && rune <= 0x309F) || // Hiragana
      (rune >= 0x30A0 && rune <= 0x30FF);   // Katakana

  bool _isKanji(int rune) =>
      (rune >= 0x4E00 && rune <= 0x9FFF);   // CJK Unified Ideographs

  bool _isHan(int rune) =>
      (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK Unified
      (rune >= 0x3400 && rune <= 0x4DBF) || // CJK Extension A
      (rune >= 0x20000 && rune <= 0x2A6DF); // CJK Extension B

  bool _isHangul(int rune) =>
      (rune >= 0xAC00 && rune <= 0xD7AF) || // Hangul Syllables
      (rune >= 0x1100 && rune <= 0x11FF);   // Hangul Jamo

  bool _isCyrillic(int rune) =>
      (rune >= 0x0400 && rune <= 0x04FF);   // Cyrillic

  bool _isArabic(int rune) =>
      (rune >= 0x0600 && rune <= 0x06FF) || // Arabic
      (rune >= 0x0750 && rune <= 0x077F);   // Arabic Supplement

  /// Disposes the HTTP client.
  void dispose() {
    _client.close();
  }
}
