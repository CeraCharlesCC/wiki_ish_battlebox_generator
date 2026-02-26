import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/wikitext_import_report.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/services/wikitext_field_extractors.dart';

void main() {
  const extractors = WikitextFieldExtractors();

  test('extractMediaImage parses multiple image and keeps trailing remainder as fragment', () {
    const input = '{{Multiple image|image1=Foo.jpg}} [[File:Bar.png]]';

    final result = extractors.extractMediaImage(input);

    expect(result.items, const ['Foo.jpg']);
    expect(result.unparsedFragments, contains('[[File:Bar.png]]'));
    expect(result.firstOffendingToken, 'multiple image');
    expect(result.status, ImportFieldStatus.partial);
  });
}
