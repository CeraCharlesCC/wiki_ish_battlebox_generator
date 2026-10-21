import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/infrastructure/platform/editor_draft_storage_stub.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/presentation/screens/battlebox_editor_screen.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/presentation/state/providers.dart';

void main() {
  String? lastCopiedText;

  setUp(() {
    lastCopiedText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            lastCopiedText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('visual edits synchronize the panel, history and local draft', (
    tester,
  ) async {
    final storage = MemoryEditorDraftStorage();
    final container = ProviderContainer(
      overrides: [editorDraftStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BattleBoxEditorScreen()),
      ),
    );
    await tester.pump();
    final editor = container.read(battleboxEditorNotifierProvider.notifier);

    editor.setTitle('Visual edit from canvas');
    await tester.pump();
    final panel = tester.widget<TextField>(find.byType(TextField).first);
    expect(panel.controller!.text, contains('Visual edit from canvas'));
    expect(editor.canUndo, isTrue);

    editor.undo();
    await tester.pump();
    expect(panel.controller!.text, contains('Battle of Exampleville'));
    expect(editor.canRedo, isTrue);
    editor.redo();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      jsonDecode(storage.read()!)['documentWikitext'],
      contains('Visual edit from canvas'),
    );
    expect(jsonDecode(storage.read()!)['manualDraft'], isFalse);
  });

  testWidgets('manual wikitext is not overwritten by visual edits', (
    tester,
  ) async {
    final storage = MemoryEditorDraftStorage();
    final container = ProviderContainer(
      overrides: [editorDraftStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BattleBoxEditorScreen()),
      ),
    );
    await tester.pump();

    final wikitext = find.byType(TextField).first;
    await tester.enterText(wikitext, 'my unimported {{template|content}}');
    await tester.pump();
    container
        .read(battleboxEditorNotifierProvider.notifier)
        .setTitle('New title');
    await tester.pump();
    expect(
      tester.widget<TextField>(wikitext).controller!.text,
      'my unimported {{template|content}}',
    );
    expect(
      find.textContaining('wikitext and visual changes conflict'),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 350));
    final draft = jsonDecode(storage.read()!) as Map<String, dynamic>;
    expect(draft['manualDraft'], isTrue);
    expect(draft['visualChangedDuringDraft'], isTrue);
    expect(draft['editorWikitext'], 'my unimported {{template|content}}');
  });

  testWidgets('reload restores visual changes and manual drafts', (
    tester,
  ) async {
    final storage = MemoryEditorDraftStorage();
    Future<ProviderContainer> showEditor() async {
      final container = ProviderContainer(
        overrides: [editorDraftStorageProvider.overrideWithValue(storage)],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: BattleBoxEditorScreen()),
        ),
      );
      await tester.pump();
      return container;
    }

    final first = await showEditor();
    first
        .read(battleboxEditorNotifierProvider.notifier)
        .setTitle('Persisted title');
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'unimported text');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpWidget(const SizedBox.shrink());
    first.dispose();

    final second = await showEditor();
    addTearDown(second.dispose);
    expect(
      second.read(battleboxEditorNotifierProvider).title,
      'Persisted title',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'unimported text',
    );
  });

  testWidgets('rejected import preserves visual document', (tester) async {
    final container = ProviderContainer(
      overrides: [
        editorDraftStorageProvider.overrideWithValue(
          MemoryEditorDraftStorage(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BattleBoxEditorScreen()),
      ),
    );
    await tester.pump();
    final currentTitle = container.read(battleboxEditorNotifierProvider).title;
    await tester.enterText(find.byType(TextField).first, 'not an infobox');
    await tester.pump();
    await tester.tap(find.text('Import'));
    await tester.pump();
    expect(container.read(battleboxEditorNotifierProvider).title, currentTitle);
    expect(find.textContaining('Import rejected'), findsOneWidget);
  });

  testWidgets('Copy after import uses the original, unnormalized source', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        editorDraftStorageProvider.overrideWithValue(
          MemoryEditorDraftStorage(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BattleBoxEditorScreen()),
      ),
    );
    await tester.pump();
    const raw =
        '{{Infobox military conflict\n'
        '| conflict = Exact original <ref>source</ref>\n'
        '| status = ongoing\n'
        '}}';
    await tester.enterText(find.byType(TextField).first, raw);
    await tester.pump();
    await tester.tap(find.text('Import'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      raw,
    );
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(lastCopiedText, raw);
  });

  testWidgets('corrupt visual recovery protects the saved raw draft', (
    tester,
  ) async {
    final storage = MemoryEditorDraftStorage();
    const raw =
        '{{Infobox military conflict\n'
        '| conflict = Recovered from wikitext\n'
        '| status = ongoing\n'
        '}}';
    storage.write(
      jsonEncode({
        'version': 1,
        'documentWikitext': 'This cannot be parsed',
        'editorWikitext': raw,
        'syncedWikitext': raw,
        'manualDraft': false,
        'visualChangedDuringDraft': false,
      }),
    );
    final container = ProviderContainer(
      overrides: [editorDraftStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BattleBoxEditorScreen()),
      ),
    );
    await tester.pump();
    expect(
      find.textContaining('saved visual document could not be restored'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      raw,
    );
    container
        .read(battleboxEditorNotifierProvider.notifier)
        .setTitle('Visual changed');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      raw,
      reason: 'a visual edit must not overwrite the recoverable draft',
    );
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy my draft'));
    await tester.pump();
    expect(lastCopiedText, raw);
  });

  testWidgets('small screens can render and edit without layout overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        editorDraftStorageProvider.overrideWithValue(
          MemoryEditorDraftStorage(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BattleBoxEditorScreen()),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    container
        .read(battleboxEditorNotifierProvider.notifier)
        .addBelligerentColumn();
    container
        .read(battleboxEditorNotifierProvider.notifier)
        .addBelligerentColumn();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Battlebox Editor'), findsOneWidget);
  });
}
