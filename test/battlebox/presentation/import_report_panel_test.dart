import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/application/ports/battlebox_serializer.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/application/usecases/battlebox_editing_usecases.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/application/usecases/export_wikitext.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/application/usecases/import_wikitext.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/battlebox_doc.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/wikitext_import_report.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/services/battlebox_editor.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/services/battlebox_seed.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/presentation/screens/battlebox_editor_screen.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/presentation/state/battlebox_editor_notifier.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/presentation/state/providers.dart';
import 'package:wiki_ish_battlebox_generator/src/core/clock.dart';
import 'package:wiki_ish_battlebox_generator/src/core/id_generator.dart';

class _FakeClock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 2, 26, 12);
}

class _NoopSerializer implements BattleboxSerializer {
  final BattleBoxDoc _doc;

  const _NoopSerializer(this._doc);

  @override
  BattleBoxDoc parse(String text) => _doc;

  @override
  String export(BattleBoxDoc doc) => '';
}

void main() {
  testWidgets('wikitext panel renders import report and unparsed fragments', (
    tester,
  ) async {
    final seedDoc = BattleboxSeed(const TimestampIdGenerator()).create();
    final report = WikitextImportReport(
      fields: const {
        'combatant1': ImportFieldReport(
          key: 'combatant1',
          status: ImportFieldStatus.partial,
          parsedItemCount: 3,
          unparsedFragments: ['{{UnknownTemplate|value=1}}'],
          firstOffendingToken: 'UnknownTemplate',
        ),
      },
    );

    final doc = seedDoc.copyWith(importReport: report);
    final serializer = _NoopSerializer(doc);
    final notifier = BattleboxEditorNotifier(
      editing: BattleboxEditingUseCases(
        editor: BattleboxEditor(
          clock: _FakeClock(),
          idGenerator: const TimestampIdGenerator(),
        ),
      ),
      importWikitext: ImportWikitext(serializer),
      exportWikitext: ExportWikitext(serializer),
      initialDoc: doc,
    );

    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          battleboxEditorNotifierProvider.overrideWith((ref) => notifier),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WikitextPanel(
              controller: controller,
              onImport: () {},
              onExport: () {},
              onCopy: () {},
              onExportImage: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Import report'), findsOneWidget);
    expect(find.textContaining('Parsed:'), findsOneWidget);
    expect(find.textContaining('combatant1'), findsWidgets);
    expect(find.text('Unparsed fragments'), findsOneWidget);
    expect(find.textContaining('{{UnknownTemplate|value=1}}'), findsOneWidget);
  });
}
