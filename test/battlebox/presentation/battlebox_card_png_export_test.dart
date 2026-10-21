import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/presentation/state/providers.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/presentation/widgets/battlebox_card.dart';

void main() {
  testWidgets('export capture includes every column at narrow viewport width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(350, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final editor = container.read(battleboxEditorNotifierProvider.notifier);
    for (var i = 2; i < 6; i++) {
      editor.addBelligerentColumn();
    }
    for (var i = 0; i < 6; i++) {
      editor.updateMultiColumnCell('combatants', i, 'Combatant ${i + 1}');
    }

    final captureKey = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: RepaintBoundary(
                  key: captureKey,
                  child: const BattleBoxCard(isExportMode: true),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final boundaryFinder = find.byKey(captureKey);
    final captureRect = tester.getRect(boundaryFinder);
    expect(captureRect.width, 6 * 112 + 2);
    expect(captureRect.width, greaterThan(tester.view.physicalSize.width));

    // The last cell must be *inside* the RepaintBoundary, not merely alive in
    // the widget tree but outside the region captured by toImage().
    final lastCell = find.descendant(
      of: boundaryFinder,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('Combatant 6'),
      ),
    );
    expect(lastCell, findsOneWidget);
    expect(
      tester.getRect(lastCell).right,
      lessThanOrEqualTo(captureRect.right),
    );
    expect(
      find.descendant(
        of: boundaryFinder,
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
      reason: 'export rows should not have their own clipped scrollports',
    );

    final boundary = tester.renderObject<RenderRepaintBoundary>(boundaryFinder);
    final png = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        expect(image.width, 6 * 112 + 2);
        return await image.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        image.dispose();
      }
    });
    expect(png, isNotNull);
    // PNG's IHDR width uses four big-endian bytes at offset 16.
    expect(png!.getUint32(16), 6 * 112 + 2);
  });

  testWidgets('editing retains a compact, horizontally scrollable card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(350, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final editor = container.read(battleboxEditorNotifierProvider.notifier);
    for (var i = 2; i < 6; i++) {
      editor.addBelligerentColumn();
    }

    final cardKey = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: RepaintBoundary(
                  key: cardKey,
                  child: const BattleBoxCard(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.getSize(find.byKey(cardKey)).width, lessThanOrEqualTo(380));
    expect(
      find.descendant(
        of: find.byKey(cardKey),
        matching: find.byType(SingleChildScrollView),
      ),
      findsWidgets,
    );
  });
}
