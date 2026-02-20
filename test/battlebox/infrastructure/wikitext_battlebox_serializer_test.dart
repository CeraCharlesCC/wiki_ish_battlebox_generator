import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/sections.dart';
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
}}
| combatant2 = Opposing force
}}
''';

    final doc = serializer.parse(input);
    final section = doc.sectionById('combatants') as MultiColumnSection;
    expect(section.cells[0].length, 1);
    final columnText = section.cells[0].map((item) => item.raw).join('\n');

    expect(columnText, contains('{{Plainlist|'));
    expect(columnText, contains('}}'));
  });

  test('parse keeps efn + plainlist block in a single combatant cell', () {
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

    expect(section.cells[0].length, 1);
    final raw = section.cells[0].first.raw;
    expect(raw, contains('{{Efn|States that fought against the emperor'));
    expect(raw, contains('{{Plainlist|'));
    expect(raw, contains('* {{Flagicon|Kingdom of Bohemia}} [[Bohemia]]'));
    expect(raw, contains('}}'));
  });
}
