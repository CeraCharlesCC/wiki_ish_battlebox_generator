import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../application/ports/wiki_icon_gateway.dart';

/// MediaWiki API implementation of WikiIconGateway.
class WikiIconMediawikiAdapter implements WikiIconGateway {
  WikiIconMediawikiAdapter({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _now = now ?? DateTime.now;

  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final Map<_CacheKey, _IconCacheEntry> _cache = {};
  final Map<_CacheKey, Future<String?>> _pending = {};

  static const Map<String, String> _defaultHosts = {
    'flagicon': 'ja.wikipedia.org',
    'flag icon': 'en.wikipedia.org',
  };

  static const String _userAgent =
      'BattleboxGenerator/0.1 (contact: https://github.com/ceracharlescc/)';

  @override
  Future<String?> resolveFlagIcon({
    required String templateName,
    required String code,
    required int widthPx,
    String? hostOverride,
  }) async {
    final host = _resolveHost(templateName, hostOverride);
    final cacheKey = _CacheKey(
      host: host,
      template: templateName.toLowerCase(),
      code: code,
      width: widthPx,
    );
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired(_now())) {
      return cached.url;
    }
    final existing = _pending[cacheKey];
    if (existing != null) {
      return existing;
    }
    final future = _fetchFlagIcon(
      host: host,
      templateName: templateName,
      code: code,
      widthPx: widthPx,
    );
    _pending[cacheKey] = future;
    try {
      final value = await future;
      if (_cache.length >= 512) _cache.remove(_cache.keys.first);
      _cache[cacheKey] = _IconCacheEntry(value, _now());
      return value;
    } finally {
      _pending.remove(cacheKey);
    }
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<http.Response?> _get(Uri uri) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client
            .get(uri, headers: {'Api-User-Agent': _userAgent})
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) return response;
        if (response.statusCode != 429 && response.statusCode < 500) {
          return null;
        }
      } catch (_) {
        // Retry transport errors once. A temporary failure is not permanent.
      }
    }
    return null;
  }

  Future<String?> _fetchFlagIcon({
    required String host,
    required String templateName,
    required String code,
    required int widthPx,
  }) async {
    final wikitext = await _expandTemplate(
      host: host,
      templateName: templateName,
      code: code,
    );
    if (wikitext == null || wikitext.isEmpty) {
      return null;
    }
    final fileName = _extractFileName(wikitext);
    if (fileName == null || fileName.isEmpty) {
      return null;
    }
    return _fetchImageInfo(host: host, fileName: fileName, widthPx: widthPx);
  }

  Future<String?> _expandTemplate({
    required String host,
    required String templateName,
    required String code,
  }) async {
    final uri = Uri.https(host, '/w/api.php', {
      'action': 'expandtemplates',
      'format': 'json',
      'formatversion': '2',
      'origin': '*',
      'text': '{{${templateName.trim()}|${code.trim()}}}',
      'prop': 'wikitext',
    });
    final resp = await _get(uri);
    if (resp == null) return null;
    final decoded = jsonDecode(resp.body);
    final expand = decoded is Map<String, dynamic>
        ? decoded['expandtemplates']
        : null;
    if (expand is Map<String, dynamic>) {
      final wikitext = expand['wikitext'];
      if (wikitext is String) {
        return wikitext;
      }
    }
    return null;
  }

  Future<String?> _fetchImageInfo({
    required String host,
    required String fileName,
    required int widthPx,
  }) async {
    final uri = Uri.https(host, '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'formatversion': '2',
      'origin': '*',
      'prop': 'imageinfo',
      'iiprop': 'url',
      'iiurlwidth': '$widthPx',
      'titles': 'File:$fileName',
    });
    final resp = await _get(uri);
    if (resp == null) return null;
    final decoded = jsonDecode(resp.body);
    final query = decoded is Map<String, dynamic> ? decoded['query'] : null;
    if (query is! Map<String, dynamic>) {
      return null;
    }
    final pages = query['pages'];
    if (pages is! List) {
      return null;
    }
    for (final page in pages) {
      if (page is! Map<String, dynamic>) {
        continue;
      }
      final imageInfo = page['imageinfo'];
      if (imageInfo is! List || imageInfo.isEmpty) {
        continue;
      }
      final first = imageInfo.first;
      if (first is! Map<String, dynamic>) {
        continue;
      }
      final thumbUrl = first['thumburl'];
      if (thumbUrl is String && thumbUrl.isNotEmpty) {
        return thumbUrl;
      }
      final url = first['url'];
      if (url is String && url.isNotEmpty) {
        return url;
      }
    }
    return null;
  }

  String? _extractFileName(String wikitext) {
    final match = RegExp(
      r'\[\[(?:File|ファイル):([^|\]]+)',
      caseSensitive: false,
    ).firstMatch(wikitext);
    return match?.group(1)?.trim();
  }

  String _resolveHost(String templateName, String? override) {
    if (override != null && override.trim().isNotEmpty) {
      return _normalizeHost(override.trim());
    }
    final key = templateName.trim().toLowerCase();
    return _defaultHosts[key] ?? 'en.wikipedia.org';
  }

  String _normalizeHost(String host) {
    var trimmed = host.trim();
    trimmed = trimmed.replaceFirst(RegExp(r'^https?://'), '');
    if (trimmed.isEmpty) {
      return 'en.wikipedia.org';
    }
    if (!trimmed.contains('.')) {
      return '$trimmed.wikipedia.org';
    }
    return trimmed;
  }
}

class _CacheKey {
  final String host;
  final String template;
  final String code;
  final int width;

  const _CacheKey({
    required this.host,
    required this.template,
    required this.code,
    required this.width,
  });

  @override
  bool operator ==(Object other) {
    return other is _CacheKey &&
        other.host == host &&
        other.template == template &&
        other.code == code &&
        other.width == width;
  }

  @override
  int get hashCode => Object.hash(host, template, code, width);
}

class _IconCacheEntry {
  final String? url;
  final DateTime timestamp;

  _IconCacheEntry(this.url, this.timestamp);

  bool isExpired(DateTime now) =>
      now.difference(timestamp) >
      (url == null ? const Duration(minutes: 5) : const Duration(days: 7));
}
