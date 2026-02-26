import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/services/wikitext_normalizer.dart';

void main() {
  const normalizer = WikitextNormalizer();

  test('normalize strips comment and ref fragments in inline mode', () {
    const input = 'Alpha<!--c--><ref name="x">r</ref>Beta';

    final result = normalizer.normalize(
      input,
      mode: NormalizationMode.inlineText,
    );

    expect(result.normalizedText, 'AlphaBeta');
    expect(result.unparsedFragments, contains('<!--c-->'));
    expect(result.unparsedFragments, contains('<ref name="x">r</ref>'));
    expect(result.firstOffendingToken, 'comment');
  });
}
