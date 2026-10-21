import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/infrastructure/http/wiki_link_mediawiki_adapter.dart';

void main() {
  test('concurrent distinct links share a failed SiteMatrix fetch', () async {
    var now = DateTime.utc(2026, 10, 21);
    var metaRequests = 0;
    var wikiRequests = 0;
    final metaStarted = Completer<void>();
    final releaseMeta = Completer<void>();
    final adapter = WikiLinkMediawikiAdapter(
      now: () => now,
      client: MockClient((request) async {
        if (request.url.host == 'meta.wikimedia.org') {
          metaRequests++;
          if (!metaStarted.isCompleted) metaStarted.complete();
          await releaseMeta.future;
          return http.Response('Service unavailable', 503);
        }
        wikiRequests++;
        return http.Response(
          jsonEncode({
            'query': {
              'pages': [
                {
                  'pageid': wikiRequests,
                  'title': request.url.queryParameters['titles'],
                  'fullurl': 'https://en.wikipedia.org/wiki/Example',
                },
              ],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(adapter.dispose);

    // Every unique title is a different resolve() cache key, but all 24
    // resolutions require the *same* SiteMatrix. Hold the first Meta response
    // to prove requests are coalesced rather than merely cached afterwards.
    final requests = [
      for (var i = 0; i < 24; i++)
        adapter.resolve(rawTarget: 'Battle $i', forcedLang: 'en'),
    ];
    await metaStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(metaRequests, 1);
    releaseMeta.complete();
    final links = await Future.wait(requests);
    expect(links.every((link) => link != null), isTrue);
    expect(wikiRequests, 24);
    expect(metaRequests, 2, reason: 'only one failed fetch with two retries');

    await adapter.resolve(rawTarget: 'One more', forcedLang: 'en');
    expect(metaRequests, 2, reason: 'fallback should have a brief cache TTL');

    now = now.add(const Duration(minutes: 6));
    await adapter.resolve(
      rawTarget: 'After fallback expires',
      forcedLang: 'en',
    );
    expect(metaRequests, 4, reason: 'failed SiteMatrix is eventually retried');
  });

  test('a recovered SiteMatrix replaces the temporary fallback', () async {
    var now = DateTime.utc(2026, 10, 21);
    var metaRequests = 0;
    var restored = false;
    final adapter = WikiLinkMediawikiAdapter(
      now: () => now,
      client: MockClient((request) async {
        expect(request.url.host, 'meta.wikimedia.org');
        metaRequests++;
        if (!restored) return http.Response('Down', 503);
        return http.Response(
          jsonEncode({
            'sitematrix': {
              '0': {
                'code': 'xx',
                'site': [
                  {'code': 'wiki', 'url': 'https://xx.wikipedia.org'},
                ],
              },
            },
          }),
          200,
        );
      }),
    );
    addTearDown(adapter.dispose);

    final fallback = await adapter.fetchSiteMatrix();
    expect(fallback['en'], 'en.wikipedia.org');
    expect(fallback.containsKey('xx'), isFalse);
    expect(metaRequests, 2);

    restored = true;
    expect((await adapter.fetchSiteMatrix()).containsKey('xx'), isFalse);
    expect(metaRequests, 2);

    now = now.add(const Duration(minutes: 6));
    expect((await adapter.fetchSiteMatrix())['xx'], 'xx.wikipedia.org');
    expect(metaRequests, 3);

    now = now.add(const Duration(days: 2));
    expect((await adapter.fetchSiteMatrix())['xx'], 'xx.wikipedia.org');
    expect(metaRequests, 3, reason: 'a healthy matrix keeps the full TTL');
  });

  test(
    'an empty but HTTP 200 SiteMatrix also uses a short-lived fallback',
    () async {
      var now = DateTime.utc(2026, 10, 21);
      var metaRequests = 0;
      final adapter = WikiLinkMediawikiAdapter(
        now: () => now,
        client: MockClient((request) async {
          metaRequests++;
          return http.Response('{"sitematrix": {"count": 0}}', 200);
        }),
      );
      addTearDown(adapter.dispose);

      expect((await adapter.fetchSiteMatrix())['ja'], 'ja.wikipedia.org');
      expect((await adapter.fetchSiteMatrix())['ja'], 'ja.wikipedia.org');
      expect(metaRequests, 1);
      now = now.add(const Duration(minutes: 6));
      expect((await adapter.fetchSiteMatrix())['ja'], 'ja.wikipedia.org');
      expect(metaRequests, 2);
    },
  );
}
