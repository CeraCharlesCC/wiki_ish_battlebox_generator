import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wiki_ish_battlebox_generator/services/wiki_link_resolver.dart';

void main() {
  group('WikiLinkResolver', () {
    group('buildNaiveUrl', () {
      late WikiLinkResolver resolver;

      setUp(() {
        resolver = WikiLinkResolver();
      });

      tearDown(() {
        resolver.dispose();
      });

      test('builds URL for English Wikipedia by default', () {
        final url = resolver.buildNaiveUrl(rawTarget: 'Battle of Gettysburg');
        expect(url, 'https://en.wikipedia.org/wiki/Battle_of_Gettysburg');
      });

      test('replaces spaces with underscores', () {
        final url = resolver.buildNaiveUrl(rawTarget: 'World War II');
        expect(url, contains('World_War_II'));
      });

      test('includes fragment when provided', () {
        final url = resolver.buildNaiveUrl(
          rawTarget: 'World War II',
          fragment: 'European theater',
        );
        expect(url, contains('#European_theater'));
      });

      test('uses langPrefix when provided', () {
        final url = resolver.buildNaiveUrl(
          rawTarget: '東京',
          langPrefix: 'ja',
        );
        expect(url, startsWith('https://ja.wikipedia.org/wiki/'));
      });

      test('detects Japanese text and uses ja wiki', () {
        final url = resolver.buildNaiveUrl(rawTarget: 'ジュノー・ビーチの戦い');
        expect(url, startsWith('https://ja.wikipedia.org/wiki/'));
      });

      test('detects Korean text and uses ko wiki', () {
        final url = resolver.buildNaiveUrl(rawTarget: '서울');
        expect(url, startsWith('https://ko.wikipedia.org/wiki/'));
      });

      test('detects Cyrillic text and uses ru wiki', () {
        final url = resolver.buildNaiveUrl(rawTarget: 'Москва');
        expect(url, startsWith('https://ru.wikipedia.org/wiki/'));
      });

      test('detects Arabic text and uses ar wiki', () {
        final url = resolver.buildNaiveUrl(rawTarget: 'القاهرة');
        expect(url, startsWith('https://ar.wikipedia.org/wiki/'));
      });

      test('URL-encodes special characters', () {
        final url = resolver.buildNaiveUrl(rawTarget: 'Test & Special');
        expect(url, contains(Uri.encodeComponent('Test_&_Special')));
      });
    });

    group('fetchSiteMatrix', () {
      test('parses SiteMatrix response correctly', () async {
        final mockClient = MockClient((request) async {
          expect(request.url.host, 'meta.wikimedia.org');
          expect(request.url.queryParameters['action'], 'sitematrix');

          return http.Response(
            jsonEncode({
              'sitematrix': {
                'count': 2,
                '0': {
                  'code': 'en',
                  'site': [
                    {'code': 'wiki', 'url': 'https://en.wikipedia.org'},
                    {'code': 'wiktionary', 'url': 'https://en.wiktionary.org'},
                  ],
                },
                '1': {
                  'code': 'ja',
                  'site': [
                    {'code': 'wiki', 'url': 'https://ja.wikipedia.org'},
                  ],
                },
                'specials': [],
              },
            }),
            200,
          );
        });

        final resolver = WikiLinkResolver(client: mockClient);
        final siteMatrix = await resolver.fetchSiteMatrix();

        expect(siteMatrix['en'], 'en.wikipedia.org');
        expect(siteMatrix['ja'], 'ja.wikipedia.org');
        expect(siteMatrix.containsKey('wiktionary'), isFalse);

        resolver.dispose();
      });

      test('returns fallback on error', () async {
        final mockClient = MockClient((request) async {
          return http.Response('Error', 500);
        });

        final resolver = WikiLinkResolver(client: mockClient);
        final siteMatrix = await resolver.fetchSiteMatrix();

        expect(siteMatrix['en'], 'en.wikipedia.org');
        expect(siteMatrix.isNotEmpty, isTrue);

        resolver.dispose();
      });
    });

    group('resolve', () {
      test('resolves existing page', () async {
        final mockClient = MockClient((request) async {
          if (request.url.queryParameters['action'] == 'sitematrix') {
            return http.Response(
              jsonEncode({
                'sitematrix': {
                  '0': {
                    'code': 'en',
                    'site': [
                      {'code': 'wiki', 'url': 'https://en.wikipedia.org'},
                    ],
                  },
                },
              }),
              200,
            );
          }

          // Query API response
          return http.Response(
            jsonEncode({
              'query': {
                'pages': [
                  {
                    'pageid': 12345,
                    'title': 'Battle of Gettysburg',
                    'fullurl': 'https://en.wikipedia.org/wiki/Battle_of_Gettysburg',
                    'canonicalurl': 'https://en.wikipedia.org/wiki/Battle_of_Gettysburg',
                  },
                ],
              },
            }),
            200,
          );
        });

        final resolver = WikiLinkResolver(client: mockClient);
        final result = await resolver.resolve(rawTarget: 'Battle of Gettysburg');

        expect(result, isNotNull);
        expect(result!.fullUrl, contains('Battle_of_Gettysburg'));
        expect(result.langCode, 'en');
        expect(result.pageId, 12345);

        resolver.dispose();
      });

      test('returns null for missing page', () async {
        final mockClient = MockClient((request) async {
          if (request.url.queryParameters['action'] == 'sitematrix') {
            return http.Response(
              jsonEncode({
                'sitematrix': {
                  '0': {
                    'code': 'en',
                    'site': [
                      {'code': 'wiki', 'url': 'https://en.wikipedia.org'},
                    ],
                  },
                },
              }),
              200,
            );
          }

          return http.Response(
            jsonEncode({
              'query': {
                'pages': [
                  {
                    'title': 'NonExistentPage12345',
                    'missing': true,
                  },
                ],
              },
            }),
            200,
          );
        });

        final resolver = WikiLinkResolver(client: mockClient);
        final result = await resolver.resolve(rawTarget: 'NonExistentPage12345');

        expect(result, isNull);

        resolver.dispose();
      });

      test('detects redirect', () async {
        final mockClient = MockClient((request) async {
          if (request.url.queryParameters['action'] == 'sitematrix') {
            return http.Response(
              jsonEncode({
                'sitematrix': {
                  '0': {
                    'code': 'en',
                    'site': [
                      {'code': 'wiki', 'url': 'https://en.wikipedia.org'},
                    ],
                  },
                },
              }),
              200,
            );
          }

          return http.Response(
            jsonEncode({
              'query': {
                'redirects': [
                  {'from': 'USA', 'to': 'United States'},
                ],
                'pages': [
                  {
                    'pageid': 3434750,
                    'title': 'United States',
                    'fullurl': 'https://en.wikipedia.org/wiki/United_States',
                  },
                ],
              },
            }),
            200,
          );
        });

        final resolver = WikiLinkResolver(client: mockClient);
        final result = await resolver.resolve(rawTarget: 'USA');

        expect(result, isNotNull);
        expect(result!.wasRedirect, isTrue);
        expect(result.resolvedTitle, 'United States');

        resolver.dispose();
      });

      test('adds fragment to resolved URL', () async {
        final mockClient = MockClient((request) async {
          if (request.url.queryParameters['action'] == 'sitematrix') {
            return http.Response(
              jsonEncode({
                'sitematrix': {
                  '0': {
                    'code': 'en',
                    'site': [
                      {'code': 'wiki', 'url': 'https://en.wikipedia.org'},
                    ],
                  },
                },
              }),
              200,
            );
          }

          return http.Response(
            jsonEncode({
              'query': {
                'pages': [
                  {
                    'pageid': 12345,
                    'title': 'World War II',
                    'fullurl': 'https://en.wikipedia.org/wiki/World_War_II',
                  },
                ],
              },
            }),
            200,
          );
        });

        final resolver = WikiLinkResolver(client: mockClient);
        final result = await resolver.resolve(
          rawTarget: 'World War II',
          fragment: 'European theater',
        );

        expect(result, isNotNull);
        expect(result!.fullUrl, contains('#European_theater'));

        resolver.dispose();
      });

      test('uses forced language', () async {
        var queriedHost = '';
        final mockClient = MockClient((request) async {
          if (request.url.queryParameters['action'] == 'sitematrix') {
            return http.Response(
              jsonEncode({
                'sitematrix': {
                  '0': {
                    'code': 'en',
                    'site': [
                      {'code': 'wiki', 'url': 'https://en.wikipedia.org'},
                    ],
                  },
                  '1': {
                    'code': 'ja',
                    'site': [
                      {'code': 'wiki', 'url': 'https://ja.wikipedia.org'},
                    ],
                  },
                },
              }),
              200,
            );
          }

          queriedHost = request.url.host;
          return http.Response(
            jsonEncode({
              'query': {
                'pages': [
                  {
                    'pageid': 12345,
                    'title': 'Tokyo',
                    'fullurl': 'https://ja.wikipedia.org/wiki/Tokyo',
                  },
                ],
              },
            }),
            200,
          );
        });

        final resolver = WikiLinkResolver(client: mockClient);
        await resolver.resolve(rawTarget: 'Tokyo', forcedLang: 'ja');

        expect(queriedHost, 'ja.wikipedia.org');

        resolver.dispose();
      });

      test('caches resolved results', () async {
        var callCount = 0;
        final mockClient = MockClient((request) async {
          if (request.url.queryParameters['action'] == 'sitematrix') {
            return http.Response(
              jsonEncode({
                'sitematrix': {
                  '0': {
                    'code': 'en',
                    'site': [
                      {'code': 'wiki', 'url': 'https://en.wikipedia.org'},
                    ],
                  },
                },
              }),
              200,
            );
          }

          callCount++;
          return http.Response(
            jsonEncode({
              'query': {
                'pages': [
                  {
                    'pageid': 12345,
                    'title': 'Test',
                    'fullurl': 'https://en.wikipedia.org/wiki/Test',
                  },
                ],
              },
            }),
            200,
          );
        });

        final resolver = WikiLinkResolver(client: mockClient);

        // First call
        await resolver.resolve(rawTarget: 'Test');
        expect(callCount, 1);

        // Second call - should use cache
        await resolver.resolve(rawTarget: 'Test');
        expect(callCount, 1);

        resolver.dispose();
      });
    });
  });

  group('ResolvedWikiLink', () {
    test('url property prefers canonicalUrl', () {
      const link = ResolvedWikiLink(
        canonicalUrl: 'https://en.wikipedia.org/wiki/Test_Canonical',
        fullUrl: 'https://en.wikipedia.org/wiki/Test',
        wikiHost: 'en.wikipedia.org',
        langCode: 'en',
      );

      expect(link.url, 'https://en.wikipedia.org/wiki/Test_Canonical');
    });

    test('url property falls back to fullUrl', () {
      const link = ResolvedWikiLink(
        fullUrl: 'https://en.wikipedia.org/wiki/Test',
        wikiHost: 'en.wikipedia.org',
        langCode: 'en',
      );

      expect(link.url, 'https://en.wikipedia.org/wiki/Test');
    });
  });
}
