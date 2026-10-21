import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_ish_battlebox_generator/src/core/clock.dart';
import 'package:wiki_ish_battlebox_generator/src/core/id_generator.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/application/usecases/battlebox_editing_usecases.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/application/usecases/export_wikitext.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/application/usecases/import_wikitext.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/sections.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/wikitext_import_report.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/services/battlebox_editor.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/infrastructure/serialization/wikitext_battlebox_serializer.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/presentation/state/battlebox_editor_notifier.dart';

void main() {
  late WikitextBattleboxSerializer serializer;

  setUp(() {
    serializer = WikitextBattleboxSerializer();
  });

  test('zero-index fields alone cannot replace a visual document', () {
    for (final key in [
      'combatant0',
      'commander0',
      'units0',
      'strength0',
      'casualties0',
      'combatant00a',
    ]) {
      expect(
        () => serializer.parse('{{Infobox military conflict|$key=X}}'),
        throwsA(isA<FormatException>()),
        reason: key,
      );
    }
  });

  test('zero-index custom fields survive alongside supported content', () {
    final doc = serializer.parse(
      '{{Infobox military conflict|conflict=Test|combatant0=X|combatant01=Army}}',
    );
    expect(doc.customFields['combatant0'], 'X');
    expect(
      doc.importReport!.fields['combatant0']!.status,
      ImportFieldStatus.partial,
    );
    final combatants = doc.sectionById('combatants') as MultiColumnSection;
    expect(combatants.cells.single.single.raw, 'Army');
    expect(serializer.export(doc), contains('| combatant0 = X'));
  });

  test('unnamed parameters warn even when multiple named fields were parsed', () {
    const unknown = '{{Unknown|critical evidence}}';
    final doc = serializer.parse(
      '{{Infobox military conflict|conflict=Test|combatant1=North|$unknown|combatant2=South}}',
    );
    final report = doc.importReport!.fields['__infobox__'];
    expect(report, isNotNull);
    expect(report!.status, ImportFieldStatus.partial);
    expect(report.unparsedFragments, [unknown]);
    expect(report.firstOffendingToken, contains('unnamed'));
    expect(doc.title, 'Test');
    final combatants = doc.sectionById('combatants') as MultiColumnSection;
    expect(combatants.cells[0].single.raw, 'North');
    expect(combatants.cells[1].single.raw, 'South');
  });

  test('nested parameter pipes do not cause an infobox loss warning', () {
    final doc = serializer.parse(
      '{{Infobox military conflict|conflict=Test|combatant1={{Bulletlist|North|South}}||}}',
    );
    expect(doc.importReport!.fields.containsKey('__infobox__'), isFalse);
  });

  test('all discarded parameters retain source diagnostics', () {
    final doc = serializer.parse(
      '{{Infobox military conflict|conflict=Test|combatant1=North'
      '|{{Unknown|a=b}}|  = unkeyed evidence|free text}}',
    );
    final report = doc.importReport!.fields['__infobox__']!;
    expect(report.status, ImportFieldStatus.partial);
    expect(report.unparsedFragments, [
      '{{Unknown|a=b}}',
      '= unkeyed evidence',
      'free text',
    ]);
    expect(report.parsedItemCount, 2);
  });

  String nestedInput(int levels) =>
      '{{Infobox military conflict|combatant1='
      '${List.filled(levels, '{{Plainlist|').join()}'
      '* Army${List.filled(levels, '}}').join()}'
      '}}';

  test('rejects excessive nesting before recursive field extraction', () {
    for (final levels in [WikitextBattleboxSerializer.maxTemplateDepth, 2000]) {
      expect(
        () => serializer.parse(nestedInput(levels)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('nesting limit'),
          ),
        ),
      );
    }
  });

  test('accepts nested templates at the documented depth boundary', () {
    final doc = serializer.parse(
      nestedInput(WikitextBattleboxSerializer.maxTemplateDepth - 1),
    );
    final combatants = doc.sectionById('combatants') as MultiColumnSection;
    expect(combatants.cells.single.single.raw, 'Army');
  });

  test('rejected imports preserve the document and undo/redo history', () {
    final initial = serializer.parse(
      '{{Infobox military conflict|conflict=Original}}',
    );
    final notifier = BattleboxEditorNotifier(
      editing: BattleboxEditingUseCases(
        editor: const BattleboxEditor(
          clock: SystemClock(),
          idGenerator: TimestampIdGenerator(),
        ),
      ),
      importWikitext: ImportWikitext(serializer),
      exportWikitext: ExportWikitext(serializer),
      initialDoc: initial,
    );
    addTearDown(notifier.dispose);
    notifier.setTitle('Edited');
    notifier.setTitle('Second edit');
    notifier.undo();
    final before = notifier.exportWikitext();
    expect(notifier.canUndo, isTrue);
    expect(notifier.canRedo, isTrue);
    for (final input in [
      '{{Infobox military conflict|combatant0=X}}',
      nestedInput(2000),
    ]) {
      expect(
        () => notifier.importWikitext(input),
        throwsA(isA<FormatException>()),
      );
    }
    expect(notifier.exportWikitext(), before);
    expect(notifier.canUndo, isTrue);
    expect(notifier.canRedo, isTrue);
    notifier.redo();
    expect(notifier.exportWikitext(), contains('Second edit'));
    notifier.undo();
    notifier.undo();
    expect(notifier.exportWikitext(), contains('Original'));
  });
}
