import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_ish_battlebox_generator/src/core/clock.dart';
import 'package:wiki_ish_battlebox_generator/src/core/id_generator.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/battlebox_doc.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/column_model.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/rich_text_value.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/sections.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/entities/wikitext_import_report.dart';
import 'package:wiki_ish_battlebox_generator/src/battlebox/domain/services/battlebox_editor.dart';

class FakeClock implements Clock {
  DateTime _now;
  FakeClock([DateTime? initialTime]) : _now = initialTime ?? DateTime(2024, 1, 1);

  void advance(Duration duration) {
    _now = _now.add(duration);
  }

  @override
  DateTime now() => _now;
}

class FakeIdGenerator implements IdGenerator {
  int _counter = 0;

  @override
  String newId() => 'id_${++_counter}';
}

void main() {
  late FakeClock clock;
  late FakeIdGenerator idGenerator;
  late BattleboxEditor editor;

  setUp(() {
    clock = FakeClock(DateTime(2024, 6, 15, 10, 30));
    idGenerator = FakeIdGenerator();
    editor = BattleboxEditor(clock: clock, idGenerator: idGenerator);
  });

  BattleBoxDoc createTestDoc() {
    return BattleBoxDoc(
      id: 'doc_1',
      title: 'Test Battle',
      sections: [
        const SingleFieldSection(id: 'result', label: 'Result'),
        const ListFieldSection(
          id: 'date',
          label: 'Date',
          items: [RichTextValue('January 1')],
        ),
        MultiColumnSection(
          id: 'combatants',
          label: 'Combatants',
          columns: [
            const ColumnModel(id: 'col_1', label: 'Belligerent 1'),
            const ColumnModel(id: 'col_2', label: 'Belligerent 2'),
          ],
          cells: [
            [const RichTextValue('Army A')],
            [const RichTextValue('Army B')],
          ],
        ),
        const MediaSection(id: 'media', label: 'Media'),
      ],
    );
  }

  group('BattleboxEditor', () {
    group('setTitle', () {
      test('updates the title and lastEdited', () {
        final doc = createTestDoc();
        final result = editor.setTitle(doc, 'Battle of New Name');

        expect(result.title, 'Battle of New Name');
        expect(result.lastEdited, clock.now());
        expect(result.id, doc.id); // ID should not change
      });
    });

    group('setSingleField', () {
      test('sets value on single field section', () {
        final doc = createTestDoc();
        final result = editor.setSingleField(doc, 'result', 'Victory');

        final section = result.sectionById('result') as SingleFieldSection;
        expect(section.value?.raw, 'Victory');
        expect(result.lastEdited, clock.now());
      });

      test('returns unchanged doc for non-existent section', () {
        final doc = createTestDoc();
        final result = editor.setSingleField(doc, 'nonexistent', 'Value');

        expect(result, doc);
      });

      test('returns unchanged doc for wrong section type', () {
        final doc = createTestDoc();
        final result = editor.setSingleField(doc, 'date', 'Value');

        expect(result.sectionById('date'), doc.sectionById('date'));
      });
    });

    group('clearSingleField', () {
      test('clears value on single field section', () {
        var doc = createTestDoc();
        doc = editor.setSingleField(doc, 'result', 'Victory');

        final result = editor.clearSingleField(doc, 'result');
        final section = result.sectionById('result') as SingleFieldSection;

        expect(section.value?.raw, '');
      });
    });

    group('addListItem', () {
      test('adds empty item to list field section', () {
        final doc = createTestDoc();
        final result = editor.addListItem(doc, 'date');

        final section = result.sectionById('date') as ListFieldSection;
        expect(section.items.length, 2);
        expect(section.items[1].raw, '');
        expect(result.lastEdited, clock.now());
      });

      test('returns unchanged doc for non-list section', () {
        final doc = createTestDoc();
        final result = editor.addListItem(doc, 'result');

        expect(result, doc);
      });
    });

    group('updateListItem', () {
      test('updates item at specified index', () {
        final doc = createTestDoc();
        final result = editor.updateListItem(doc, 'date', 0, 'February 2');

        final section = result.sectionById('date') as ListFieldSection;
        expect(section.items[0].raw, 'February 2');
      });

      test('returns unchanged doc for out of bounds index', () {
        final doc = createTestDoc();
        final result = editor.updateListItem(doc, 'date', 5, 'Value');

        expect(result.sectionById('date'), doc.sectionById('date'));
      });

      test('returns unchanged doc for negative index', () {
        final doc = createTestDoc();
        final result = editor.updateListItem(doc, 'date', -1, 'Value');

        expect(result.sectionById('date'), doc.sectionById('date'));
      });
    });

    group('deleteListItem', () {
      test('deletes item at specified index', () {
        var doc = createTestDoc();
        doc = editor.addListItem(doc, 'date');
        doc = editor.updateListItem(doc, 'date', 1, 'Second date');

        final result = editor.deleteListItem(doc, 'date', 0);
        final section = result.sectionById('date') as ListFieldSection;

        expect(section.items.length, 1);
        expect(section.items[0].raw, 'Second date');
      });

      test('returns unchanged doc for out of bounds index', () {
        final doc = createTestDoc();
        final result = editor.deleteListItem(doc, 'date', 10);

        final section = result.sectionById('date') as ListFieldSection;
        expect(section.items.length, 1);
      });
    });

    group('updateMultiColumnCell', () {
      test('updates cell at specified column with split lines', () {
        final doc = createTestDoc();
        final result = editor.updateMultiColumnCell(
          doc,
          'combatants',
          0,
          'Line 1\nLine 2',
        );

        final section = result.sectionById('combatants') as MultiColumnSection;
        expect(section.cells[0].length, 2);
        expect(section.cells[0][0].raw, 'Line 1');
        expect(section.cells[0][1].raw, 'Line 2');
      });

      test('returns unchanged doc for out of bounds column', () {
        final doc = createTestDoc();
        final result = editor.updateMultiColumnCell(doc, 'combatants', 5, 'Value');

        expect(result.sectionById('combatants'), doc.sectionById('combatants'));
      });
    });

    group('addBelligerentColumn', () {
      test('adds column to all multi-column sections', () {
        final doc = createTestDoc();
        final result = editor.addBelligerentColumn(doc);

        final section = result.sectionById('combatants') as MultiColumnSection;
        expect(section.columns.length, 3);
        expect(section.columns[2].label, 'Belligerent 3');
        expect(section.columns[2].id, 'id_1');
        expect(section.cells.length, 3);
        expect(section.cells[2][0].raw, '');
      });
    });

    group('deleteBelligerentColumn', () {
      test('deletes column from all multi-column sections', () {
        final doc = createTestDoc();
        final result = editor.deleteBelligerentColumn(doc, 1);

        final section = result.sectionById('combatants') as MultiColumnSection;
        expect(section.columns.length, 1);
        expect(section.columns[0].label, 'Belligerent 1');
        expect(section.cells.length, 1);
        expect(section.cells[0][0].raw, 'Army A');
      });

      test('returns unchanged doc for negative index', () {
        const report = WikitextImportReport(fields: {});
        final originalLastEdited = clock.now();
        final doc = createTestDoc().copyWith(
          importReport: report,
          lastEdited: originalLastEdited,
        );

        final result = editor.deleteBelligerentColumn(doc, -1);

        expect(result, same(doc));
        expect(result.lastEdited, originalLastEdited);
        expect(result.importReport, same(report));
      });

      test('returns unchanged doc if only one column remains', () {
        const report = WikitextImportReport(fields: {});
        final originalLastEdited = clock.now();
        var doc = createTestDoc();
        doc = editor.deleteBelligerentColumn(doc, 0);
        doc = doc.copyWith(
          importReport: report,
          lastEdited: originalLastEdited,
        );

        // Now try to delete the last column
        final result = editor.deleteBelligerentColumn(doc, 0);

        final section = result.sectionById('combatants') as MultiColumnSection;
        expect(section.columns.length, 1); // Should still have 1 column
        expect(result, same(doc));
        expect(result.lastEdited, originalLastEdited);
        expect(result.importReport, same(report));
      });

      test('returns unchanged doc for out of bounds index', () {
        const report = WikitextImportReport(fields: {});
        final originalLastEdited = clock.now();
        final doc = createTestDoc().copyWith(
          importReport: report,
          lastEdited: originalLastEdited,
        );
        final result = editor.deleteBelligerentColumn(doc, 10);

        final section = result.sectionById('combatants') as MultiColumnSection;
        expect(section.columns.length, 2);
        expect(result, same(doc));
        expect(result.lastEdited, originalLastEdited);
        expect(result.importReport, same(report));
      });
    });

    group('setMedia', () {
      test('updates media section fields', () {
        final doc = createTestDoc();
        final result = editor.setMedia(
          doc,
          imageUrl: 'https://example.com/image.png',
          caption: 'Battle scene',
          size: '300px',
          upright: '1.2',
        );

        final section = result.sectionById('media') as MediaSection;
        expect(section.imageUrl, 'https://example.com/image.png');
        expect(section.caption, 'Battle scene');
        expect(section.size, '300px');
        expect(section.upright, '1.2');
        expect(result.lastEdited, clock.now());
      });

      test('updates only specified fields', () {
        var doc = createTestDoc();
        doc = editor.setMedia(doc, imageUrl: 'https://example.com/image.png');
        doc = editor.setMedia(doc, caption: 'New caption');

        final section = doc.sectionById('media') as MediaSection;
        expect(section.imageUrl, 'https://example.com/image.png');
        expect(section.caption, 'New caption');
      });
    });

    group('replaceDoc', () {
      test('replaces document with updated lastEdited', () {
        final oldDoc = createTestDoc();
        final newDoc = BattleBoxDoc(
          id: 'new_id',
          title: 'New Battle',
          sections: [],
        );

        final result = editor.replaceDoc(oldDoc, newDoc);

        expect(result.id, 'new_id');
        expect(result.title, 'New Battle');
        expect(result.lastEdited, clock.now());
      });
    });

    group('import report lifecycle', () {
      test('mutating edit clears importReport', () {
        const report = WikitextImportReport(fields: {});
        final doc = createTestDoc().copyWith(importReport: report);

        final result = editor.setTitle(doc, 'Updated battle title');

        expect(result.importReport, isNull);
      });

      test('no-op edit keeps importReport', () {
        const report = WikitextImportReport(fields: {});
        final doc = createTestDoc().copyWith(importReport: report);

        final result = editor.updateListItem(doc, 'date', 99, 'Ignored');

        expect(result.importReport, isNotNull);
      });
    });
  });
}
