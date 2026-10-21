import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/wikitext_import_report.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/services/wikitext_field_extractors.dart';

void main() {
  const extractors = WikitextFieldExtractors();

  test(
    'extractMediaImage parses multiple image and keeps trailing remainder as fragment',
    () {
      const input = '{{Multiple image|image1=Foo.jpg}} [[File:Bar.png]]';

      final result = extractors.extractMediaImage(input);

      expect(result.items, const ['Foo.jpg']);
      expect(result.unparsedFragments, contains('[[File:Bar.png]]'));
      expect(result.firstOffendingToken, 'multiple image');
      expect(result.status, ImportFieldStatus.partial);
    },
  );

  test(
    'extractMediaImage reports additional images that need raw preservation',
    () {
      const original = '{{Multiple image|image1=First.jpg|image2=Second.png}}';
      final result = extractors.extractMediaImage(original);

      expect(result.items, const ['First.jpg']);
      expect(result.unparsedFragments, contains(original));
      expect(result.firstOffendingToken, 'multiple image');
      expect(result.status, ImportFieldStatus.partial);
    },
  );

  test(
    'list extraction preserves reference markup with nested HTML separators',
    () {
      const raw =
          'Alpha<ref name="x">One<br>Two {{Nested|keep=all}}</ref><br>Beta';
      final result = extractors.extractCombatant(raw);

      expect(result.items, [
        'Alpha<ref name="x">One<br>Two {{Nested|keep=all}}</ref>',
        'Beta',
      ]);
      expect(result.firstOffendingToken, 'ref');
      expect(result.status, ImportFieldStatus.partial);
    },
  );

  test('horizontal rule conversion is flagged as potentially lossy', () {
    final result = extractors.extractCasualties('First<hr />Second');

    expect(result.items, ['First', 'Second']);
    expect(result.status, ImportFieldStatus.partial);
    expect(result.firstOffendingToken, 'horizontal rule');
  });
}
