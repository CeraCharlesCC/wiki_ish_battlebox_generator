import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/services/wikitext_balanced_scanner.dart';

void main() {
  const scanner = WikitextBalancedScanner();

  test('infobox params are not split inside nested list templates', () {
    const input = '''
{{Infobox military conflict
| conflict = Example
| territory = {{Bulletlist|One {{Sfn|Ref|2024|pp=22}}|Two}}
| combatant1 = Side A
}}
''';

    final values = scanner.parseInfoboxParams(input);

    expect(values['territory'], isNotNull);
    expect(values['territory'], contains('{{Bulletlist|'));
    expect(values['territory'], contains('pp=22'));
    expect(values['combatant1'], 'Side A');
  });

  test('params are not split inside ref blocks containing pipes and equals', () {
    const input = '''
{{Infobox military conflict
| conflict = Example
| combatant1 = Alpha<ref name="x">a|b=c</ref><br>Beta
| combatant2 = Gamma
}}
''';

    final values = scanner.parseInfoboxParams(input);

    expect(values['combatant1'], contains('<ref name="x">a|b=c</ref>'));
    expect(values['combatant1'], contains('Beta'));
    expect(values['combatant2'], 'Gamma');
  });

  test('unbalanced template throws format exception', () {
    const input =
        '{{Infobox military conflict| conflict = Example | combatant1 = {{Plainlist|* A}}';

    expect(
      () => scanner.parseInfoboxParams(input),
      throwsA(isA<FormatException>()),
    );
  });
}
