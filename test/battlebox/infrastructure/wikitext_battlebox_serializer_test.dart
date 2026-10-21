import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/sections.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/rich_text_value.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/wikitext_import_report.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/infrastructure/serialization/wikitext_battlebox_serializer.dart';

void main() {
  late WikitextBattleboxSerializer serializer;

  setUp(() {
    serializer = WikitextBattleboxSerializer();
  });

  test('parse merges suffixed combatant keys into the same column', () {
    const input = '''
{{Infobox military conflict
| conflict = Example battle
| combatant1 = Base force
| combatant1a = Reinforcement A
| combatant1b = Reinforcement B
| combatant2 = Opposing force
}}
''';

    final doc = serializer.parse(input);
    final section = doc.sectionById('combatants') as MultiColumnSection;

    expect(section.cells[0].map((item) => item.raw), [
      'Base force',
      'Reinforcement A',
      'Reinforcement B',
    ]);
    expect(section.cells[1].map((item) => item.raw), ['Opposing force']);
    expect(doc.customFields.containsKey('combatant1a'), isFalse);
    expect(doc.customFields.containsKey('combatant1b'), isFalse);
  });

  test('parse preserves nested template lines inside a field value', () {
    const input = '''
{{Infobox military conflict
| conflict = Example battle
| combatant1 = Intro{{Plainlist|
* Item A
* Item B
}}
| combatant2 = Opposing force
}}
''';

    final doc = serializer.parse(input);
    final section = doc.sectionById('combatants') as MultiColumnSection;
    expect(section.cells[0].map((item) => item.raw), [
      'Intro',
      'Item A',
      'Item B',
    ]);

    final columnText = section.cells[0].map((item) => item.raw).join('\n');
    expect(columnText, isNot(contains('{{Plainlist|')));
  });

  test('parse keeps best-effort items and diagnostics for mixed templates', () {
    const input = """
{{Infobox military conflict
| conflict = Example battle
| combatant1 = '''Anti-Habsburg alliance prior to 1635'''{{Efn|States that fought against the emperor at some point between 1618 and 1635.}}{{Plainlist|
* {{Flagicon|Kingdom of Bohemia}} [[Bohemia]]
* {{Flagicon|Swedish Empire}} [[Sweden]]
}}
| combatant2 = Opposing force
}}
""";

    final doc = serializer.parse(input);
    final section = doc.sectionById('combatants') as MultiColumnSection;

    expect(section.cells[0].length, greaterThanOrEqualTo(3));
    expect(
      section.cells[0].map((item) => item.raw).join('\n'),
      isNot(contains('{{Plainlist|')),
    );
    expect(
      section.cells[0].first.raw,
      contains("'''Anti-Habsburg alliance prior to 1635'''"),
    );

    final report = doc.importReport;
    expect(report, isNotNull);
    final fieldReport = report!.fields['combatant1'];
    expect(fieldReport, isNotNull);
    expect(fieldReport!.status, ImportFieldStatus.partial);
    expect(fieldReport.unparsedFragments, isNotEmpty);
    expect(fieldReport.firstOffendingToken, isNotNull);
  });

  test(
    'parse reports __infobox__ failure when balanced parse is suspicious',
    () {
      const input = '''
{{Infobox military conflict
| conflict = Example battle
| {{Plainlist| * one | * two | * three | * four }}
}}
''';

      final doc = serializer.parse(input);

      final report = doc.importReport;
      expect(report, isNotNull);

      final topLevel = report!.fields['__infobox__'];
      expect(topLevel, isNotNull);
      expect(topLevel!.status, ImportFieldStatus.failed);
      expect(topLevel.unparsedFragments, isNotEmpty);
      expect(
        topLevel.unparsedFragments.first,
        contains('{{Infobox military conflict'),
      );
      expect(
        topLevel.firstOffendingToken,
        contains('Balanced parser produced too few infobox fields.'),
      );
    },
  );

  test(
    'single-parameter infobox with nested pipes uses the balanced parser',
    () {
      const input =
          '{{Infobox military conflict|combatant1={{Bulletlist|A|B|C}}}}';
      final doc = serializer.parse(input);
      final section = doc.sectionById('combatants') as MultiColumnSection;
      expect(section.cells.single.map((item) => item.raw), ['A', 'B', 'C']);
      expect(doc.importReport!.fields.containsKey('__infobox__'), isFalse);
      expect(doc.title, isEmpty);
    },
  );

  test(
    'parse extracts outer infobox when comment and ref contain stray braces',
    () {
      const input = '''
{{Infobox military conflict
| conflict = Example battle
| combatant1 = Army A<!-- stray {{ in comment --><ref name="n">{{broken</ref>
| combatant2 = Army B
}}
''';

      final doc = serializer.parse(input);

      expect(doc.title, 'Example battle');
    },
  );

  test('ignores infobox templates inside comments and references', () {
    const input = '''
<!-- {{Infobox military conflict|conflict=Commented out}} -->
<ref name="example">{{Infobox military conflict|conflict=Reference only}}</ref>
{{Infobox military conflict
| conflict = Actual battle
| combatant1 = Army
}}
''';
    final doc = serializer.parse(input);
    expect(doc.title, 'Actual battle');
  });

  test(
    'rejects unknown, incomplete and empty wikitext instead of resetting',
    () {
      for (final input in [
        '',
        'ordinary article prose',
        '{{Infobox person|name=Someone}}',
        '{{Infobox military conflict|conflict=Incomplete',
        '{{Infobox military conflict|unrecognized=only}}',
        '{{Infobox military conflict|conflict=}}',
      ]) {
        expect(
          () => serializer.parse(input),
          throwsA(isA<FormatException>()),
          reason: 'Should reject invalid input: $input',
        );
      }
    },
  );

  test('bounds column indices to prevent untrusted allocations', () {
    for (final index in ['33', '999999', '9999999999999999999999999999']) {
      expect(
        () => serializer.parse(
          '{{Infobox military conflict|conflict=Test|combatant$index=Risk}}',
        ),
        throwsA(isA<FormatException>()),
      );
    }

    final doc = serializer.parse(
      '{{Infobox military conflict|conflict=Test|combatant32=Last}}',
    );
    final combatants = doc.sectionById('combatants') as MultiColumnSection;
    expect(
      combatants.columns,
      hasLength(WikitextBattleboxSerializer.maxColumns),
    );
    expect(combatants.cells.last.single.raw, 'Last');
  });

  test('rejects wikitext exceeding the import size limit', () {
    final input = List.filled(
      WikitextBattleboxSerializer.maxWikitextLength + 1,
      'a',
    ).join();
    expect(() => serializer.parse(input), throwsA(isA<FormatException>()));
  });

  test('preserves source status key and visual edits on export', () {
    final doc = serializer.parse('''
{{Infobox military conflict
| conflict = Status test
| status = Ceasefire
}}
''');
    final result = doc.sectionById('result') as SingleFieldSection;
    expect(result.value?.raw, 'Ceasefire');

    final original = serializer.export(doc);
    expect(original, contains('| status = Ceasefire'));
    expect(original, isNot(contains('| result =')));

    final edited = doc.copyWith(
      sections: [
        for (final section in doc.sections)
          if (section is SingleFieldSection && section.id == 'result')
            section.copyWith(value: const RichTextValue('Ongoing'))
          else
            section,
      ],
    );
    final afterEdit = serializer.export(edited);
    expect(afterEdit, contains('| status = Ongoing'));
    expect(afterEdit, isNot(contains('| result =')));
  });

  test('preserves distinct status and result keys when both exist', () {
    final doc = serializer.parse('''
{{Infobox military conflict
| conflict = Both keys
| result = Victory
| status = Active
}}
''');
    final wikitext = serializer.export(doc);
    expect(wikitext, contains('| result = Victory'));
    expect(wikitext, contains('| status = Active'));
  });

  test('round-trips all images while previewing the first one', () {
    const source = '''
{{Infobox military conflict
| conflict = Multiple images
| image = {{Multiple image|image1=First.jpg|image2=Second.png|caption2=Second caption}}
}}
''';
    final doc = serializer.parse(source);
    final media = doc.sectionById('media') as MediaSection;
    expect(media.imageUrl, 'First.jpg');
    expect(
      doc.importReport!.fields['image']!.status,
      ImportFieldStatus.partial,
    );

    final converted = serializer.export(doc);
    expect(converted, contains('image2=Second.png'));
    expect(converted, contains('caption2=Second caption'));
    expect(RegExp(r'\| image =').allMatches(converted), hasLength(1));

    final edited = doc.copyWith(
      sections: [
        for (final section in doc.sections)
          if (section is MediaSection)
            section.copyWith(imageUrl: 'Replacement.jpg')
          else
            section,
      ],
    );
    expect(serializer.export(edited), contains('| image = Replacement.jpg'));
    expect(serializer.export(edited), isNot(contains('image2=Second.png')));
  });

  test('preserves refs, unsupported templates and inline formatting', () {
    const input = """
{{Infobox military conflict
| conflict = Reference example
| combatant1 = '''Bold'''  <ref name="source">X|Y=Z</ref> {{Unrecognized|keep=original}}
| combatant2 = Other side
}}
""";
    final doc = serializer.parse(input);
    final combatants = doc.sectionById('combatants') as MultiColumnSection;
    final text = combatants.cells[0].map((item) => item.raw).join('\n');
    expect(text, contains('<ref name="source">X|Y=Z</ref>'));
    expect(text, contains('{{Unrecognized|keep=original}}'));
    expect(text, contains('  '));
    expect(serializer.export(doc), contains('{{Unrecognized|keep=original}}'));
    expect(
      doc.importReport!.fields['combatant1']!.status,
      ImportFieldStatus.partial,
    );
  });

  test('keeps line breaks inside references within a single visual item', () {
    const input = '''
{{Infobox military conflict
| conflict = Protected references
| date = 1 July<ref name="date">First<br>Second</ref><br>2 July
| place = [[Northbridge]]<ref>Coast<br>Harbor</ref>
| combatant1 = Army<ref name="source">A<br>B</ref><br />Militia
| combatant2 = Rivals
}}
''';
    final doc = serializer.parse(input);
    final combatants = doc.sectionById('combatants') as MultiColumnSection;
    final dates = doc.sectionById('date') as ListFieldSection;
    final places = doc.sectionById('location') as ListFieldSection;

    expect(combatants.cells[0].map((item) => item.raw), [
      'Army<ref name="source">A<br>B</ref>',
      'Militia',
    ]);
    expect(dates.items.map((item) => item.raw), [
      '1 July<ref name="date">First<br>Second</ref>',
      '2 July',
    ]);
    expect(
      places.items.single.raw,
      '[[Northbridge]]<ref>Coast<br>Harbor</ref>',
    );
    expect(serializer.export(doc), contains('A<br>B</ref>'));
    expect(serializer.export(doc), contains('First<br>Second</ref>'));
  });
}
