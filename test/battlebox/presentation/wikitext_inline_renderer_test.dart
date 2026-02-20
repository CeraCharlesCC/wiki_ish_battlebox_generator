import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/application/ports/external_link_opener.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/application/ports/wiki_icon_gateway.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/application/ports/wiki_link_gateway.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/presentation/state/providers.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/presentation/widgets/wikitext_inline_renderer.dart';

class _FakeExternalLinkOpener implements ExternalLinkOpener {
  @override
  Future<bool> open(Uri uri) async => false;
}

class _FakeWikiIconGateway implements WikiIconGateway {
  @override
  Future<String?> resolveFlagIcon({
    required String templateName,
    required String code,
    required int widthPx,
    String? hostOverride,
  }) async {
    return null;
  }

  @override
  void dispose() {}
}

class _FakeWikiLinkGateway implements WikiLinkGateway {
  @override
  Future<ResolvedWikiLink?> resolve({
    required String rawTarget,
    String? fragment,
    String? forcedLang,
    String defaultLang = 'en',
  }) async {
    return null;
  }

  @override
  String buildNaiveUrl({
    required String rawTarget,
    String? fragment,
    String? langPrefix,
    String defaultLang = 'en',
  }) {
    return 'https://$defaultLang.wikipedia.org/wiki/$rawTarget';
  }

  @override
  Future<Map<String, String>> fetchSiteMatrix() async => {};

  @override
  void dispose() {}
}

Widget _buildTestWidget(String text, {bool isInteractive = true}) {
  return ProviderScope(
    overrides: [
      wikiIconGatewayProvider.overrideWithValue(_FakeWikiIconGateway()),
      wikiLinkGatewayProvider.overrideWithValue(_FakeWikiLinkGateway()),
      externalLinkOpenerProvider.overrideWithValue(_FakeExternalLinkOpener()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: WikitextInlineRenderer(
          text: text,
          isInteractive: isInteractive,
        ),
      ),
    ),
  );
}

Finder _findRichTextContaining(String text) {
  return find.byWidgetPredicate((widget) {
    if (widget is RichText) {
      return widget.text.toPlainText().contains(text);
    }
    return false;
  });
}

void main() {
  testWidgets('plainlist renders bullets and items', (tester) async {
    const input = '{{Plainlist| * First item\n* Second item}}';
    await tester.pumpWidget(_buildTestWidget(input));

    expect(find.textContaining('•'), findsNWidgets(2));
    expect(_findRichTextContaining('First item'), findsOneWidget);
    expect(_findRichTextContaining('Second item'), findsOneWidget);
  });

  testWidgets('bulletlist renders bullets and items', (tester) async {
    const input = '{{Bulletlist| First item | Second item}}';
    await tester.pumpWidget(_buildTestWidget(input));

    expect(find.textContaining('•'), findsNWidgets(2));
    expect(_findRichTextContaining('First item'), findsOneWidget);
    expect(_findRichTextContaining('Second item'), findsOneWidget);
  });

  testWidgets('efn renders a marker', (tester) async {
    const input = 'Alpha{{Efn|Note text}}Beta';
    await tester.pumpWidget(_buildTestWidget(input));

    expect(find.text('a'), findsOneWidget);
  });

  testWidgets('tapping efn marker shows note dialog', (tester) async {
    const input = 'Alpha{{Efn|Note text}}Beta';
    await tester.pumpWidget(_buildTestWidget(input));

    await tester.tap(find.text('a'));
    await tester.pumpAndSettle();

    expect(find.text('Note'), findsOneWidget);
    expect(_findRichTextContaining('Note text'), findsOneWidget);
  });
}
