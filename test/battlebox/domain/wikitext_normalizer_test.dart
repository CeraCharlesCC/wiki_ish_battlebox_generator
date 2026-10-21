import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/services/wikitext_normalizer.dart';

void main() {
  const normalizer = WikitextNormalizer();

  test(
    'normalize preserves comments and refs while reporting their limitations',
    () {
      const input = 'Alpha<!--c--><ref name="x">r</ref>Beta';

      final result = normalizer.normalize(
        input,
        mode: NormalizationMode.inlineText,
      );

      expect(result.normalizedText, input);
      expect(result.unparsedFragments, contains('<!--c-->'));
      expect(result.unparsedFragments, contains('<ref name="x">r</ref>'));
      expect(result.firstOffendingToken, 'comment');
    },
  );

  test('retains unsupported templates and surrounding formatting', () {
    const input = "'''Bold'''  {{Unsupported|note=<ref>source</ref>}}  plain";
    final result = normalizer.normalize(
      input,
      mode: NormalizationMode.inlineText,
    );

    expect(result.normalizedText, input);
    expect(
      result.unparsedFragments,
      contains('{{Unsupported|note=<ref>source</ref>}}'),
    );
    expect(result.firstOffendingToken, 'Unsupported');
  });

  test('preserves unclosed templates as raw text with a warning', () {
    const input = 'Before {{Unclosed|note=important';
    final result = normalizer.normalize(
      input,
      mode: NormalizationMode.inlineText,
    );

    expect(result.normalizedText, input);
    expect(result.firstOffendingToken, 'unbalanced-template');
  });
}
