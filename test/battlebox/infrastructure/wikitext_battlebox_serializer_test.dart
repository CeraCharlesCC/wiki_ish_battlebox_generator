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
    final columnText = section.cells[0].map((item) => item.raw).join('\n');

    expect(columnText, contains('{{Plainlist|'));
    expect(columnText, contains('}}'));
  });
}
