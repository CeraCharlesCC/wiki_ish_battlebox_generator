import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/battlebox_doc.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/sections.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/wikitext_import_report.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/infrastructure/serialization/wikitext_battlebox_serializer.dart';

void main() {
  late WikitextBattleboxSerializer serializer;

  setUp(() {
    serializer = WikitextBattleboxSerializer();
  });

  test('regression fixture 1 parses targeted fields with diagnostics', () {
    final input = _readFixture('1.txt');
    final doc = serializer.parse(input);

    _expectTargetedSectionMinimums(doc);
    _expectNoPrimaryTemplateLeakage(doc);
    _expectDiagnosticsQuality(doc);
    _expectCoverageThresholds(
      doc.importReport!,
      expectedMinimums: const {
        'combatant': 8,
        'commander': 8,
        'strength': 4,
        'casualties': 4,
      },
    );
  });

  test('regression fixture 2 parses targeted fields with diagnostics', () {
    final input = _readFixture('2.txt');
    final doc = serializer.parse(input);

    _expectTargetedSectionMinimums(doc);
    _expectNoPrimaryTemplateLeakage(doc);
    _expectDiagnosticsQuality(doc);

    final media = doc.sectionById('media') as MediaSection;
    expect(media.imageUrl?.trim(), isNotEmpty);
    expect(media.imageUrl!.toLowerCase(), isNot(contains('{{multiple image')));

    _expectCoverageThresholds(
      doc.importReport!,
      expectedMinimums: const {
        'combatant': 8,
        'commander': 8,
        'strength': 4,
        'casualties': 8,
      },
    );
  });
}

String _readFixture(String name) {
  return File('test_val_dataset/$name').readAsStringSync();
}

void _expectTargetedSectionMinimums(BattleBoxDoc doc) {
  final combatants = doc.sectionById('combatants') as MultiColumnSection;
  final commanders = doc.sectionById('commanders') as MultiColumnSection;
  final strength = doc.sectionById('strength') as MultiColumnSection;
  final casualties = doc.sectionById('casualties') as MultiColumnSection;

  expect(_countNonEmpty(combatants, 0), greaterThanOrEqualTo(3));
  expect(_countNonEmpty(combatants, 1), greaterThanOrEqualTo(2));

  expect(_countNonEmpty(commanders, 0), greaterThanOrEqualTo(3));
  expect(_countNonEmpty(commanders, 1), greaterThanOrEqualTo(3));

  expect(
    strength.cells.asMap().keys.any((index) => _countNonEmpty(strength, index) >= 2),
    isTrue,
  );
  expect(
    casualties.cells
        .asMap()
        .keys
        .any((index) => _countNonEmpty(casualties, index) >= 2),
    isTrue,
  );
}

void _expectNoPrimaryTemplateLeakage(BattleBoxDoc doc) {
  final sections = <MultiColumnSection>[
    doc.sectionById('combatants') as MultiColumnSection,
    doc.sectionById('commanders') as MultiColumnSection,
    doc.sectionById('strength') as MultiColumnSection,
    doc.sectionById('casualties') as MultiColumnSection,
  ];

  const banned = <String>[
    '{{plainlist',
    '{{bulletlist',
    '{{flatlist',
    '{{collapsible list',
    '{{multiple image',
    '{{endplainlist',
    '{{flagcountry',
    '{{flagdeco',
    '{{flag|',
    '{{sfn',
    '{{sfnp',
    '{{cite',
    '{{citation needed',
  ];

  for (final section in sections) {
    for (final cell in section.cells) {
      for (final value in cell) {
        final text = value.raw.toLowerCase();
        for (final token in banned) {
          expect(text, isNot(contains(token)));
        }
      }
    }
  }
}

void _expectDiagnosticsQuality(BattleBoxDoc doc) {
  final report = doc.importReport;
  expect(report, isNotNull);
  final nonNullReport = report!;

  const requiredKeys = ['combatant1', 'commander1', 'strength1', 'casualties1'];
  for (final key in requiredKeys) {
    final field = nonNullReport.fields[key];
    expect(field, isNotNull, reason: 'Expected report entry for $key');
    expect(
      field!.status,
      anyOf(ImportFieldStatus.parsed, ImportFieldStatus.partial),
      reason: 'Expected parsed/partial status for $key',
    );
  }

  final problematic = nonNullReport.fields.values.where(
    (field) =>
        field.status == ImportFieldStatus.partial ||
        field.status == ImportFieldStatus.failed,
  );
  for (final field in problematic) {
    expect(field.firstOffendingToken, isNotNull);
    expect(field.unparsedFragments, isNotEmpty);
  }
}

void _expectCoverageThresholds(
  WikitextImportReport report, {
  required Map<String, int> expectedMinimums,
}) {
  for (final entry in expectedMinimums.entries) {
    final prefix = entry.key;
    final minItems = entry.value;
    final fields = report.fields.values
        .where((field) => field.key.toLowerCase().startsWith(prefix))
        .toList();

    expect(fields, isNotEmpty, reason: 'Expected report fields for $prefix*');
    final parsedTotal = fields.fold<int>(
      0,
      (sum, field) => sum + field.parsedItemCount,
    );
    expect(
      parsedTotal,
      greaterThanOrEqualTo(minItems),
      reason: 'Expected parsed-item coverage for $prefix* >= $minItems',
    );
  }
}

int _countNonEmpty(MultiColumnSection section, int index) {
  if (index < 0 || index >= section.cells.length) {
    return 0;
  }
  return section.cells[index].where((value) => value.raw.trim().isNotEmpty).length;
}
