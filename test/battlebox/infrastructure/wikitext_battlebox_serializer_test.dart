import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/sections.dart';
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
    expect(section.cells[0].first.raw, contains("'''Anti-Habsburg alliance prior to 1635'''"));

    final report = doc.importReport;
    expect(report, isNotNull);
    final fieldReport = report!.fields['combatant1'];
    expect(fieldReport, isNotNull);
    expect(fieldReport!.status, ImportFieldStatus.partial);
    expect(fieldReport.unparsedFragments, isNotEmpty);
    expect(fieldReport.firstOffendingToken, isNotNull);
  });

  test('parse reports __infobox__ failure when balanced parse is suspicious', () {
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
    expect(topLevel.unparsedFragments.first, contains('{{Infobox military conflict'));
    expect(
      topLevel.firstOffendingToken,
      contains('Balanced parser produced too few infobox fields.'),
    );
  });

  test('parse extracts outer infobox when comment and ref contain stray braces', () {
    const input = '''
{{Infobox military conflict
| conflict = Example battle
| combatant1 = Army A<!-- stray {{ in comment --><ref name="n">{{broken</ref>
| combatant2 = Army B
}}
''';

    final doc = serializer.parse(input);

    expect(doc.title, 'Example battle');
  });
}
