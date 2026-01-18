import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_ish_battlebox_generator/services/wikitext_inline_parser.dart';

void main() {
  const parser = WikitextInlineParser();

  group('WikitextInlineParser', () {
    group('plain text', () {
      test('parses empty string', () {
        final tokens = parser.parse('');
        expect(tokens, hasLength(1));
        expect(tokens.first, isA<InlineText>());
        expect((tokens.first as InlineText).text, '');
      });

      test('parses plain text without markup', () {
        final tokens = parser.parse('Hello world');
        expect(tokens, hasLength(1));
        expect(tokens.first, isA<InlineText>());
        expect((tokens.first as InlineText).text, 'Hello world');
      });
    });

    group('icon macros', () {
      test('parses {{flagicon|USA}}', () {
        final tokens = parser.parse('{{flagicon|USA}}');
        expect(tokens, hasLength(1));
        expect(tokens.first, isA<InlineIconMacro>());
        final macro = tokens.first as InlineIconMacro;
        expect(macro.templateName, 'flagicon');
        expect(macro.code, 'USA');
        expect(macro.hostOverride, isNull);
      });

      test('parses {{flag icon|GBR}}', () {
        final tokens = parser.parse('{{flag icon|GBR}}');
        expect(tokens, hasLength(1));
        final macro = tokens.first as InlineIconMacro;
        expect(macro.templateName, 'flag icon');
        expect(macro.code, 'GBR');
      });

      test('parses {{flagicon|JPN|host=ja}}', () {
        final tokens = parser.parse('{{flagicon|JPN|host=ja}}');
        expect(tokens, hasLength(1));
        final macro = tokens.first as InlineIconMacro;
        expect(macro.code, 'JPN');
        expect(macro.hostOverride, 'ja');
      });

      test('preserves fallbackText', () {
        const raw = '{{flagicon|USA}}';
        final tokens = parser.parse(raw);
        final macro = tokens.first as InlineIconMacro;
        expect(macro.fallbackText, raw);
      });

      test('treats unknown templates as text', () {
        final tokens = parser.parse('{{unknown|param}}');
        expect(tokens, hasLength(1));
        expect(tokens.first, isA<InlineText>());
        expect((tokens.first as InlineText).text, '{{unknown|param}}');
      });
    });

    group('wiki links', () {
      test('parses [[Target]]', () {
        final tokens = parser.parse('[[Battle of Gettysburg]]');
        expect(tokens, hasLength(1));
        expect(tokens.first, isA<InlineWikiLink>());
        final link = tokens.first as InlineWikiLink;
        expect(link.rawTarget, 'Battle of Gettysburg');
        expect(link.displayText, 'Battle of Gettysburg');
        expect(link.fragment, isNull);
      });

      test('parses [[Target|Label]]', () {
        final tokens = parser.parse('[[Battle of Gettysburg|the battle]]');
        expect(tokens, hasLength(1));
        final link = tokens.first as InlineWikiLink;
        expect(link.rawTarget, 'Battle of Gettysburg');
        expect(link.displayText, 'the battle');
      });

      test('parses [[Page#Section|Label]]', () {
        final tokens = parser.parse('[[World War II#European theater|Europe]]');
        expect(tokens, hasLength(1));
        final link = tokens.first as InlineWikiLink;
        expect(link.rawTarget, 'World War II');
        expect(link.displayText, 'Europe');
        expect(link.fragment, 'European theater');
      });

      test('parses [[#Section|Label]] (section-only link)', () {
        final tokens = parser.parse('[[#References|refs]]');
        expect(tokens, hasLength(1));
        final link = tokens.first as InlineWikiLink;
        expect(link.rawTarget, '');
        expect(link.displayText, 'refs');
        expect(link.fragment, 'References');
      });

      test('parses [[#Section]] without label', () {
        final tokens = parser.parse('[[#History]]');
        expect(tokens, hasLength(1));
        final link = tokens.first as InlineWikiLink;
        expect(link.displayText, 'History');
        expect(link.fragment, 'History');
      });

      test('applies pipe trick for [[Help:Template|]]', () {
        final tokens = parser.parse('[[Help:Template|]]');
        expect(tokens, hasLength(1));
        final link = tokens.first as InlineWikiLink;
        expect(link.displayText, 'Template');
      });

      test('applies pipe trick removing trailing parenthetical', () {
        final tokens = parser.parse('[[Washington (state)|]]');
        expect(tokens, hasLength(1));
        final link = tokens.first as InlineWikiLink;
        expect(link.displayText, 'Washington');
      });

      test('applies pipe trick removing trailing comma disambiguation', () {
        final tokens = parser.parse('[[Paris, Texas|]]');
        expect(tokens, hasLength(1));
        final link = tokens.first as InlineWikiLink;
        expect(link.displayText, 'Paris');
      });

      test('handles multiple pipes (takes first as target, last as label)', () {
        final tokens = parser.parse('[[File:Example.png|thumb|Caption]]');
        expect(tokens, hasLength(1));
        final link = tokens.first as InlineWikiLink;
        expect(link.rawTarget, 'File:Example.png');
        expect(link.displayText, 'Caption');
      });

      test('parses interlanguage link :ja:Title', () {
        final tokens = parser.parse('[[:ja:東京]]');
        expect(tokens, hasLength(1));
        final link = tokens.first as InlineWikiLink;
        expect(link.langPrefix, 'ja');
        expect(link.rawTarget, '東京');
      });

      test('parses Japanese wiki link', () {
        final tokens = parser.parse('[[ジュノー・ビーチの戦い]]');
        expect(tokens, hasLength(1));
        final link = tokens.first as InlineWikiLink;
        expect(link.rawTarget, 'ジュノー・ビーチの戦い');
        expect(link.displayText, 'ジュノー・ビーチの戦い');
      });
    });

    group('external links', () {
      test('parses [https://example.com Label]', () {
        final tokens = parser.parse('[https://example.com Example Site]');
        expect(tokens, hasLength(1));
        expect(tokens.first, isA<InlineExternalLink>());
        final link = tokens.first as InlineExternalLink;
        expect(link.uri.toString(), 'https://example.com');
        expect(link.displayText, 'Example Site');
      });

      test('parses [https://example.com] without label', () {
        final tokens = parser.parse('[https://example.com]');
        expect(tokens, hasLength(1));
        final link = tokens.first as InlineExternalLink;
        expect(link.displayText, 'https://example.com');
      });

      test('parses [http://example.com Label] with http', () {
        final tokens = parser.parse('[http://example.com Test]');
        expect(tokens, hasLength(1));
        final link = tokens.first as InlineExternalLink;
        expect(link.uri.scheme, 'http');
      });
    });

    group('bare URLs', () {
      test('parses bare https:// URL', () {
        final tokens = parser.parse('Visit https://example.com for info');
        expect(tokens, hasLength(3));
        expect(tokens[0], isA<InlineText>());
        expect(tokens[1], isA<InlineBareUrl>());
        expect(tokens[2], isA<InlineText>());
        expect((tokens[1] as InlineBareUrl).uri.toString(), 'https://example.com');
      });

      test('parses bare http:// URL', () {
        final tokens = parser.parse('See http://example.com');
        expect(tokens, hasLength(2));
        expect(tokens[1], isA<InlineBareUrl>());
      });

      test('handles URL with path and query', () {
        final tokens = parser.parse('https://example.com/path?query=value');
        expect(tokens, hasLength(1));
        final url = tokens.first as InlineBareUrl;
        expect(url.uri.path, '/path');
        expect(url.uri.queryParameters['query'], 'value');
      });
    });

    group('mixed content', () {
      test('parses text with flagicon and wiki link', () {
        final tokens = parser.parse('Text {{flagicon|us}} [[Foo]] more');
        expect(tokens, hasLength(5));
        expect(tokens[0], isA<InlineText>());
        expect(tokens[1], isA<InlineIconMacro>());
        expect(tokens[2], isA<InlineText>());
        expect(tokens[3], isA<InlineWikiLink>());
        expect(tokens[4], isA<InlineText>());
      });

      test('parses text with external link', () {
        final tokens = parser.parse('Check [https://x.com site] for details');
        expect(tokens, hasLength(3));
        expect(tokens[0], isA<InlineText>());
        expect(tokens[1], isA<InlineExternalLink>());
        expect(tokens[2], isA<InlineText>());
      });

      test('handles complex mixed content', () {
        final text = '{{flagicon|USA}} General [[George Washington|Washington]] '
            'fought at [https://en.wikipedia.org/wiki/Battle wiki]';
        final tokens = parser.parse(text);
        expect(tokens.whereType<InlineIconMacro>(), hasLength(1));
        expect(tokens.whereType<InlineWikiLink>(), hasLength(1));
        expect(tokens.whereType<InlineExternalLink>(), hasLength(1));
      });
    });

    group('edge cases', () {
      test('handles unclosed {{ as text', () {
        final tokens = parser.parse('Hello {{ world');
        expect(tokens, hasLength(1));
        expect((tokens.first as InlineText).text, 'Hello {{ world');
      });

      test('handles unclosed [[ as text', () {
        final tokens = parser.parse('Hello [[ world');
        expect(tokens, hasLength(1));
        expect((tokens.first as InlineText).text, 'Hello [[ world');
      });

      test('handles nested brackets in wiki link', () {
        // This is a simple case - we don't support true nesting
        final tokens = parser.parse('[[Outer]]');
        expect(tokens.whereType<InlineWikiLink>(), hasLength(1));
      });

      test('handles empty wiki link', () {
        final tokens = parser.parse('[[]]');
        expect(tokens, hasLength(1));
        final link = tokens.first as InlineWikiLink;
        expect(link.rawTarget, '');
        expect(link.displayText, '');
      });
    });
  });
}
