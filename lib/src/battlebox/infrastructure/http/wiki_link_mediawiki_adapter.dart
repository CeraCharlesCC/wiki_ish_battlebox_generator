import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../application/ports/wiki_link_gateway.dart';

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

/// MediaWiki API implementation of WikiLinkGateway.
class WikiLinkMediawikiAdapter implements WikiLinkGateway {
  WikiLinkMediawikiAdapter({http.Client? client})
      : _client = client ?? http.Client();

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

      _siteMatrixCache = _SiteMatrixCacheEntry(langToHost, DateTime.now());
      return langToHost;
    } catch (_) {
      return _getFallbackSiteMatrix();
    }
  }

  @override
  void dispose() {
    _client.close();
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

    for (final lang in candidates) {
      final host = siteMatrix[lang]!;
      final result = await _probeTitle(rawTarget, host, lang);
      if (result != null) {
        return result;
      }
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
      (rune >= 0x3040 && rune <= 0x309F) ||
      (rune >= 0x30A0 && rune <= 0x30FF);

  bool _isHan(int rune) =>
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x20000 && rune <= 0x2A6DF);

  bool _isHangul(int rune) =>
      (rune >= 0xAC00 && rune <= 0xD7AF) ||
      (rune >= 0x1100 && rune <= 0x11FF);

  bool _isCyrillic(int rune) =>
      (rune >= 0x0400 && rune <= 0x04FF);

  bool _isArabic(int rune) =>
      (rune >= 0x0600 && rune <= 0x06FF) ||
      (rune >= 0x0750 && rune <= 0x077F);
}
