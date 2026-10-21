import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/infrastructure/http/wiki_link_mediawiki_adapter.dart';

void main() {
  test(
    'transient Wikipedia failures are retried, not cached as missing',
    () async {
      var working = false;
      var requests = 0;
      final adapter = WikiLinkMediawikiAdapter(
        client: MockClient((request) async {
          if (request.url.host == 'meta.wikimedia.org') {
            return http.Response('Unavailable', 503); // SiteMatrix fallback.
          }
          requests++;
          if (!working) return http.Response('Temporary outage', 503);
          return http.Response(
            jsonEncode({
              'query': {
                'pages': [
                  {
                    'pageid': 42,
                    'title': 'Battle of Example',
                    'fullurl':
                        'https://en.wikipedia.org/wiki/Battle_of_Example',
                  },
                ],
              },
            }),
            200,
          );
        }),
      );
      addTearDown(adapter.dispose);

      await expectLater(
        adapter.resolve(rawTarget: 'Battle of Example', forcedLang: 'en'),
        throwsStateError,
      );
      expect(requests, 2);

      working = true;
      final result = await adapter.resolve(
        rawTarget: 'Battle of Example',
        forcedLang: 'en',
      );
      expect(result?.pageId, 42);
      expect(requests, 3);
      // A successful lookup is reused.
      expect(
        (await adapter.resolve(
          rawTarget: 'Battle of Example',
          forcedLang: 'en',
        ))?.pageId,
        42,
      );
      expect(requests, 3);
    },
  );

  test('definitively missing pages expire from the negative cache', () async {
    var now = DateTime.utc(2026, 1, 1);
    var exists = false;
    var calls = 0;
    final adapter = WikiLinkMediawikiAdapter(
      now: () => now,
      client: MockClient((request) async {
        if (request.url.host == 'meta.wikimedia.org') {
          return http.Response('Unavailable', 503);
        }
        calls++;
        return http.Response(
          jsonEncode({
            'query': {
              'pages': [
                exists
                    ? {
                        'pageid': 7,
                        'fullurl': 'https://en.wikipedia.org/wiki/Now_exists',
                      }
                    : {'missing': true},
              ],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(adapter.dispose);

    expect(
      await adapter.resolve(rawTarget: 'Now exists', forcedLang: 'en'),
      isNull,
    );
    exists = true;
    expect(
      await adapter.resolve(rawTarget: 'Now exists', forcedLang: 'en'),
      isNull,
    );
    expect(calls, 1);
    now = now.add(const Duration(hours: 2));
    expect(
      (await adapter.resolve(
        rawTarget: 'Now exists',
        forcedLang: 'en',
      ))?.pageId,
      7,
    );
    expect(calls, 2);
  });
}
