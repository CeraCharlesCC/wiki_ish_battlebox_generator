import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/services/wikitext_inline_parser.dart';

void main() {
  const parser = WikitextInlineParser();

  test('nested templates in plainlist keep full item text', () {
    const input = '{{Plainlist| * {{flagicon|USA}} [[United States|US]] }}';
    final tokens = parser.parse(input);

    expect(tokens.length, 1);
    final list = tokens.first as InlinePlainlistMacro;
    expect(list.itemRaws, const ['{{flagicon|USA}} [[United States|US]]']);
  });

  test('plainlist items allow wiki link pipes', () {
    const input = '{{Plainlist| * [[Page|Label]] }}';
    final tokens = parser.parse(input);

    expect(tokens.length, 1);
    final list = tokens.first as InlinePlainlistMacro;
    expect(list.itemRaws, const ['[[Page|Label]]']);
  });

  test('efn extraction splits surrounding text', () {
    const input = 'foo{{Efn|bar}}baz';
    final tokens = parser.parse(input);

    expect(tokens.length, 3);
    expect((tokens[0] as InlineText).text, 'foo');
    expect((tokens[1] as InlineEfnMacro).noteRaw, 'bar');
    expect((tokens[2] as InlineText).text, 'baz');
  });

  test('unclosed plainlist stays as text', () {
    const input = '{{Plainlist|';
    final tokens = parser.parse(input);

    expect(tokens.length, 1);
    expect((tokens.first as InlineText).text, '{{Plainlist|');
  });

  test('file links do not use trailing media options as label', () {
    const input = '[[File:Wappen Heilbronn.svg|18px|class=noviewer]]';
    final tokens = parser.parse(input);

    expect(tokens.length, 1);
    final link = tokens.first as InlineWikiLink;
    expect(link.rawTarget, 'File:Wappen Heilbronn.svg');
    expect(link.displayText, 'File:Wappen Heilbronn.svg');
  });
}
