import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../application/ports/wiki_image_gateway.dart';

class _CachedImage {
  final String? url;
  final DateTime storedAt;

  _CachedImage(this.url) : storedAt = DateTime.now();

  bool get expired =>
      DateTime.now().difference(storedAt) >
      (url == null ? const Duration(minutes: 5) : const Duration(days: 7));
}

/// Wikipedia filenames are not URLs. MediaWiki imageinfo resolves them to a
/// thumbnail URL, including images hosted on Wikimedia Commons.
class WikiImageMediawikiAdapter implements WikiImageGateway {
  WikiImageMediawikiAdapter({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Map<String, _CachedImage> _cache = {};
  final Map<String, Future<String?>> _pending = {};

  @override
  Future<String?> resolveImageUrl(String source, {int widthPx = 760}) async {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty) {
      return trimmed;
    }
    final fileName = _fileName(trimmed);
    if (fileName == null) return null;
    final width = widthPx.clamp(32, 1600).toInt();
    final key = '$fileName|$width';
    final cached = _cache[key];
    if (cached != null && !cached.expired) return cached.url;
    final pending = _pending[key];
    if (pending != null) return pending;
    final future = _lookup(fileName, width);
    _pending[key] = future;
    try {
      final result = await future;
      _cache[key] = _CachedImage(result);
      return result;
    } finally {
      _pending.remove(key);
    }
  }

  static String? _fileName(String input) {
    var value = input;
    if (value.startsWith('[[') && value.endsWith(']]')) {
      value = value.substring(2, value.length - 2).split('|').first.trim();
    }
    value = value
        .replaceFirst(
          RegExp(r'^(File|Image|ファイル|画像)\s*:', caseSensitive: false),
          '',
        )
        .trim();
    if (value.isEmpty ||
        value.length > 240 ||
        value.contains(RegExp(r'[\n\r{}\[\]<>]')) ||
        value.contains('://')) {
      return null;
    }
    return value.replaceAll('_', ' ');
  }

  Future<String?> _lookup(String fileName, int width) async {
    // Most Commons images can also be found through the Wikipedia API. The
    // Commons fallback covers files absent from the English wiki's repository.
    for (final host in const ['en.wikipedia.org', 'commons.wikimedia.org']) {
      final uri = Uri.https(host, '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'formatversion': '2',
        'origin': '*',
        'prop': 'imageinfo',
        'iiprop': 'url',
        'iiurlwidth': '$width',
        'titles': 'File:$fileName',
      });
      try {
        final response = await _client
            .get(uri)
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) continue;
        final json = jsonDecode(response.body);
        if (json is! Map<String, dynamic>) continue;
        final query = json['query'];
        if (query is! Map<String, dynamic>) continue;
        final pages = query['pages'];
        if (pages is! List) continue;
        for (final page in pages) {
          if (page is! Map<String, dynamic>) continue;
          final imageInfo = page['imageinfo'];
          if (imageInfo is! List || imageInfo.isEmpty) continue;
          final info = imageInfo.first;
          if (info is! Map<String, dynamic>) continue;
          final thumb = info['thumburl'];
          if (thumb is String && thumb.startsWith('https://')) return thumb;
          final direct = info['url'];
          if (direct is String && direct.startsWith('https://')) return direct;
        }
      } catch (_) {
        // Failed requests must not prevent image previews or PNG captures.
      }
    }
    return null;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
