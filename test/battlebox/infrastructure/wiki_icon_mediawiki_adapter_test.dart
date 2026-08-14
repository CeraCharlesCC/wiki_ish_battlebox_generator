import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/infrastructure/http/wiki_icon_mediawiki_adapter.dart';

void main() {
  test('failed flag resolution can be retried', () async {
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
              'expandtemplates': {
                'wikitext': '[[File:Example flag.svg|23px]]',
              },
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

    await expectLater(
      adapter.resolveFlagIcon(
        templateName: 'flagicon',
        code: 'USA',
        widthPx: 32,
      ),
      throwsException,
    );

    final result = await adapter.resolveFlagIcon(
      templateName: 'flagicon',
      code: 'USA',
      widthPx: 32,
    );

    expect(result, 'https://example.test/example-flag.png');
    expect(requestCount, 3);
  });
}
