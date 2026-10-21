import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../application/ports/wiki_link_gateway.dart';

/// Cache entry for resolved wiki links.
class _ResolveCacheEntry {
  final ResolvedWikiLink? result;
  final DateTime timestamp;

  const _ResolveCacheEntry(this.result, this.timestamp);

  bool isExpired(Duration ttl, DateTime now) => now.difference(timestamp) > ttl;
}

/// Cache entry for SiteMatrix data.
class _SiteMatrixCacheEntry {
  final Map<String, String> langToHost;
  final DateTime timestamp;
  final bool isFallback;

  const _SiteMatrixCacheEntry(
    this.langToHost,
    this.timestamp, {
    this.isFallback = false,
  });

  bool isExpired(Duration ttl, DateTime now) => now.difference(timestamp) > ttl;
}

/// MediaWiki API implementation of WikiLinkGateway.
class WikiLinkMediawikiAdapter implements WikiLinkGateway {
  WikiLinkMediawikiAdapter({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _now = now ?? DateTime.now;

  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;

  static const String _userAgent =
      'BattleboxGenerator/0.1 (contact: https://github.com/ceracharlescc/)';

  // Cache TTLs
  static const Duration _siteMatrixTtl = Duration(days: 7);
  // An outage must not keep the reduced language list for a whole week.
  static const Duration _siteMatrixFallbackTtl = Duration(minutes: 5);
  static const Duration _resolveTtl = Duration(days: 7);
  static const Duration _negativeCacheTtl = Duration(hours: 1);

  // Maximum number of language candidates to probe
  static const int _maxProbeCount = 5;

  // Caches
  _SiteMatrixCacheEntry? _siteMatrixCache;
  Future<Map<String, String>>? _pendingSiteMatrix;
  final Map<String, _ResolveCacheEntry> _resolveCache = {};
  final Map<String, Future<ResolvedWikiLink?>> _pending = {};

  @override
  Future<ResolvedWikiLink?> resolve({
    required String rawTarget,
    String? fragment,
    String? forcedLang,
    String defaultLang = 'en',
  }) async {
    if (rawTarget.trim().isEmpty) {
      return null;
    }

    final cacheKey = _makeCacheKey(rawTarget, forcedLang, defaultLang);

    // Check cache first
    final cached = _resolveCache[cacheKey];
    if (cached != null) {
      final ttl = cached.result == null ? _negativeCacheTtl : _resolveTtl;
      if (!cached.isExpired(ttl, _now())) {
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
      if (_resolveCache.length >= 1024) {
        _resolveCache.remove(_resolveCache.keys.first);
      }
      _resolveCache[cacheKey] = _ResolveCacheEntry(result, _now());
      return _addFragment(result, fragment);
    } finally {
      _pending.remove(cacheKey);
    }
  }

  @override
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

  @override
  Future<Map<String, String>> fetchSiteMatrix() async {
    final cached = _siteMatrixCache;
    if (cached != null &&
        !cached.isExpired(
          cached.isFallback ? _siteMatrixFallbackTtl : _siteMatrixTtl,
          _now(),
        )) {
      return cached.langToHost;
    }

    // Different link targets have different resolve() keys. Without a shared
    // in-flight SiteMatrix request they can all fetch (and retry) Meta at once.
    final pending = _pendingSiteMatrix;
    if (pending != null) return pending;

    final future = _loadSiteMatrix();
    _pendingSiteMatrix = future;
    try {
      return await future;
    } finally {
      if (identical(_pendingSiteMatrix, future)) _pendingSiteMatrix = null;
    }
  }

  Future<Map<String, String>> _loadSiteMatrix() async {
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
      final resp = await _get(uri);

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        return _cacheFallbackSiteMatrix();
      }

      final sitematrix = decoded['sitematrix'];
      if (sitematrix is! Map<String, dynamic>) {
        return _cacheFallbackSiteMatrix();
      }

      final langToHost = <String, String>{};

      for (final entry in sitematrix.entries) {
        if (entry.key == 'count' || entry.key == 'specials') continue;

        final langData = entry.value;
        if (langData is! Map<String, dynamic>) continue;

        final code = langData['code'];
        if (code is! String) continue;

        final sites = langData['site'];
        if (sites is! List) continue;

        for (final site in sites) {
          if (site is! Map<String, dynamic>) continue;
          if (site['code'] == 'wiki') {
            final url = site['url'];
            if (url is String) {
              final host = url.replaceFirst(RegExp(r'^https?://'), '');
              langToHost[code] = host;
              break;
            }
          }
        }
      }

      if (langToHost.isEmpty) return _cacheFallbackSiteMatrix();
      _siteMatrixCache = _SiteMatrixCacheEntry(langToHost, _now());
      return langToHost;
    } catch (_) {
      return _cacheFallbackSiteMatrix();
    }
  }

  Map<String, String> _cacheFallbackSiteMatrix() {
    final fallback = _getFallbackSiteMatrix();
    _siteMatrixCache = _SiteMatrixCacheEntry(
      fallback,
      _now(),
      isFallback: true,
    );
    return fallback;
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
  }

  /// Throws for transient request failures, so they cannot be cached as
  /// definite 'page missing' results and painted as redlinks.
  Future<http.Response> _get(Uri uri) async {
    Object? failure;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client
            .get(uri, headers: {'Api-User-Agent': _userAgent})
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) return response;
        failure = StateError(
          'MediaWiki request returned HTTP ${response.statusCode}',
        );
        if (response.statusCode != 429 && response.statusCode < 500) break;
      } catch (error) {
        failure = error;
      }
    }
    throw StateError('Unable to verify Wikipedia page: $failure');
  }

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

  Future<ResolvedWikiLink?> _resolveInternal({
    required String rawTarget,
    String? forcedLang,
    required String defaultLang,
  }) async {
    final siteMatrix = await fetchSiteMatrix();

    final candidates = <String>[];

    if (forcedLang != null && siteMatrix.containsKey(forcedLang)) {
      candidates.add(forcedLang);
    } else {
      final detected = _detectLanguageCandidates(rawTarget, defaultLang);
      for (final lang in detected) {
        if (siteMatrix.containsKey(lang)) {
          candidates.add(lang);
        }
        if (candidates.length >= _maxProbeCount) break;
      }
    }

    Object? requestFailure;
    for (final lang in candidates) {
      final host = siteMatrix[lang]!;
      try {
        final result = await _probeTitle(rawTarget, host, lang);
        if (result != null) return result;
      } catch (error) {
        requestFailure ??= error;
      }
    }

    if (requestFailure != null) {
      throw StateError(
        'Wikipedia availability could not be verified: $requestFailure',
      );
    }

    return null;
  }

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

    final resp = await _get(uri);

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected MediaWiki response');
    }

    final query = decoded['query'];
    if (query is! Map<String, dynamic>) {
      throw const FormatException('Missing query in MediaWiki response');
    }

    final redirects = query['redirects'];
    final wasRedirect = redirects is List && redirects.isNotEmpty;

    final pages = query['pages'];
    if (pages is! List || pages.isEmpty) {
      throw const FormatException('Missing pages in MediaWiki response');
    }

    final page = pages.first;
    if (page is! Map<String, dynamic>) {
      throw const FormatException('Malformed page in MediaWiki response');
    }

    if (page['missing'] == true) {
      return null;
    }

    final pageId = page['pageid'];
    final canonicalUrl = page['canonicalurl'];
    final fullUrl = page['fullurl'];
    final resolvedTitle = page['title'];

    if (fullUrl is! String) {
      throw const FormatException('No page URL in MediaWiki response');
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
  }

  String? _detectPrimaryLanguage(String text) {
    if (text.isEmpty) return null;

    var kanaCount = 0;
    var hangulCount = 0;
    var cyrillicCount = 0;
    var arabicCount = 0;
    var hanCount = 0;
    var meaningfulTotal = 0;

    for (final rune in text.runes) {
      if (_isIgnorableForLangDetect(rune)) {
        continue;
      }
      meaningfulTotal++;

      if (_isKana(rune)) {
        kanaCount++;
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

    if (meaningfulTotal == 0) return null;

    if (kanaCount > 0) {
      return 'ja';
    }
    if (hangulCount > meaningfulTotal * 0.3) {
      return 'ko';
    }
    if (cyrillicCount > meaningfulTotal * 0.3) {
      return 'ru';
    }
    if (arabicCount > meaningfulTotal * 0.3) {
      return 'ar';
    }
    if (hanCount > meaningfulTotal * 0.3) {
      return 'zh';
    }

    return null;
  }

  bool _isIgnorableForLangDetect(int rune) {
    if (rune <= 0x20) return true;
    if (rune >= 0x30 && rune <= 0x39) return true;
    if ((rune >= 0x21 && rune <= 0x2F) ||
        (rune >= 0x3A && rune <= 0x40) ||
        (rune >= 0x5B && rune <= 0x60) ||
        (rune >= 0x7B && rune <= 0x7E)) {
      return true;
    }
    return false;
  }

  List<String> _detectLanguageCandidates(String text, String defaultLang) {
    final candidates = <String>[];

    final primary = _detectPrimaryLanguage(text);
    if (primary != null) {
      candidates.add(primary);

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

    if (!candidates.contains(defaultLang)) {
      candidates.add(defaultLang);
    }

    if (primary == null) {
      candidates.addAll(['es', 'fr', 'de', 'pt', 'it']);
    }

    return candidates;
  }

  String _makeCacheKey(
    String rawTarget,
    String? forcedLang,
    String defaultLang,
  ) {
    return '${forcedLang ?? ''}|$defaultLang|$rawTarget';
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
      (rune >= 0x3040 && rune <= 0x309F) || (rune >= 0x30A0 && rune <= 0x30FF);

  bool _isHan(int rune) =>
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x20000 && rune <= 0x2A6DF);

  bool _isHangul(int rune) =>
      (rune >= 0xAC00 && rune <= 0xD7AF) || (rune >= 0x1100 && rune <= 0x11FF);

  bool _isCyrillic(int rune) => (rune >= 0x0400 && rune <= 0x04FF);

  bool _isArabic(int rune) =>
      (rune >= 0x0600 && rune <= 0x06FF) || (rune >= 0x0750 && rune <= 0x077F);
}
