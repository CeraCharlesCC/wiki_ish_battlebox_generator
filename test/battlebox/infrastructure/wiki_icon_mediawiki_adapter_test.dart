import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/infrastructure/http/wiki_icon_mediawiki_adapter.dart';

void main() {
  test('transient request failure is retried during flag resolution', () async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      if (requestCount == 1) {
        throw Exception('temporary network failure');
      }

      switch (request.url.queryParameters['action']) {
        case 'expandtemplates':
          return http.Response(
            jsonEncode({
              'expandtemplates': {'wikitext': '[[File:Example flag.svg|23px]]'},
            }),
            200,
          );
        case 'query':
          return http.Response(
            jsonEncode({
              'query': {
                'pages': [
                  {
                    'imageinfo': [
                      {'thumburl': 'https://example.test/example-flag.png'},
                    ],
                  },
                ],
              },
            }),
            200,
          );
        default:
          return http.Response('Not found', 404);
      }
    });
    final adapter = WikiIconMediawikiAdapter(client: client);
    addTearDown(adapter.dispose);

    final result = await adapter.resolveFlagIcon(
      templateName: 'flagicon',
      code: 'USA',
      widthPx: 32,
    );
    expect(result, 'https://example.test/example-flag.png');
    expect(requestCount, 3);

    expect(
      await adapter.resolveFlagIcon(
        templateName: 'flagicon',
        code: 'USA',
        widthPx: 32,
      ),
      result,
    );
    expect(requestCount, 3, reason: 'successful resolutions are cached');
  });

  test('failed lookups have a short-lived negative cache', () async {
    var now = DateTime.utc(2026, 10, 1);
    var requests = 0;
    final adapter = WikiIconMediawikiAdapter(
      now: () => now,
      client: MockClient((request) async {
        requests++;
        return http.Response('No icon', 404);
      }),
    );
    addTearDown(adapter.dispose);

    Future<String?> resolve() => adapter.resolveFlagIcon(
      templateName: 'flagicon',
      code: 'NO_MATCH',
      widthPx: 24,
    );

    expect(await resolve(), isNull);
    expect(await resolve(), isNull);
    expect(requests, 1);

    now = now.add(const Duration(minutes: 6));
    expect(await resolve(), isNull);
    expect(requests, 2, reason: 'a failed icon is retried after TTL');
  });
}
