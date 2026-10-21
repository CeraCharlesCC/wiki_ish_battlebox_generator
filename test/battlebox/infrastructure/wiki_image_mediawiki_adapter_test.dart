import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/infrastructure/http/wiki_image_mediawiki_adapter.dart';

void main() {
  test('resolves a Wikipedia filename to a thumbnail URL', () async {
    final urls = <Uri>[];
    final adapter = WikiImageMediawikiAdapter(
      client: MockClient((request) async {
        urls.add(request.url);
        return http.Response(
          jsonEncode({
            'query': {
              'pages': [
                {
                  'imageinfo': [
                    {
                      'thumburl':
                          'https://upload.wikimedia.org/example-thumb.png',
                    },
                  ],
                },
              ],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(adapter.dispose);

    final resolved = await adapter.resolveImageUrl(
      '[[File:Example flag.svg|thumb]]',
    );
    expect(resolved, 'https://upload.wikimedia.org/example-thumb.png');
    expect(urls, hasLength(1));
    expect(urls.single.queryParameters['titles'], 'File:Example flag.svg');
    expect(urls.single.queryParameters['iiurlwidth'], '760');

    // Successful lookups are cached; direct URLs skip the API entirely.
    expect(await adapter.resolveImageUrl('File:Example flag.svg'), resolved);
    expect(
      await adapter.resolveImageUrl('https://example.test/image.png'),
      'https://example.test/image.png',
    );
    expect(urls, hasLength(1));
  });

  test('missing or malformed images do not throw', () async {
    var calls = 0;
    final adapter = WikiImageMediawikiAdapter(
      client: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'query': {
              'pages': [
                {'missing': true},
              ],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(adapter.dispose);

    expect(await adapter.resolveImageUrl('{{unresolved template}}'), isNull);
    expect(calls, 0);
    expect(await adapter.resolveImageUrl('Unknown image.svg'), isNull);
    // Wikipedia then Commons are consulted before treating a file as absent.
    expect(calls, 2);
  });
}
