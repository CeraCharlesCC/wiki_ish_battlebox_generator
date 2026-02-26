import '../../../core/clock.dart';
import '../../../core/id_generator.dart';
import '../../../core/iterable_ext.dart';
import '../entities/battlebox_doc.dart';
import '../entities/column_model.dart';
import '../entities/rich_text_value.dart';
import '../entities/sections.dart';

/// Pure domain service encapsulating all battlebox document editing rules.
///
/// All methods are pure transformations: they take a document and return
/// an updated document without side effects.
class BattleboxEditor {
  final Clock _clock;
  final IdGenerator _idGenerator;

  const BattleboxEditor({
    required Clock clock,
    required IdGenerator idGenerator,
  })  : _clock = clock,
        _idGenerator = idGenerator;

  /// Replaces the entire document, updating lastEdited.
  BattleBoxDoc replaceDoc(BattleBoxDoc doc, BattleBoxDoc newDoc) {
    return newDoc.copyWith(lastEdited: _clock.now());
  }

  /// Updates the document title.
  BattleBoxDoc setTitle(BattleBoxDoc doc, String title) {
    final updated = doc.copyWith(title: title, lastEdited: _clock.now());
    return _clearImportReportIfPresent(updated);
  }

  /// Sets the value of a single-field section.
  BattleBoxDoc setSingleField(
    BattleBoxDoc doc,
    String sectionId,
    String value,
  ) {
    final section = doc.sectionById(sectionId);
    if (section is! SingleFieldSection) {
      return doc;
    }
    final updated = section.copyWith(value: RichTextValue(value));
    return _replaceSection(doc, sectionId, updated);
  }

  /// Clears the value of a single-field section.
  BattleBoxDoc clearSingleField(BattleBoxDoc doc, String sectionId) {
    final section = doc.sectionById(sectionId);
    if (section is! SingleFieldSection) {
      return doc;
    }
    final updated = section.copyWith(value: const RichTextValue(''));
    return _replaceSection(doc, sectionId, updated);
  }

  /// Adds a new empty item to a list-field section.
  BattleBoxDoc addListItem(BattleBoxDoc doc, String sectionId) {
    final section = doc.sectionById(sectionId);
    if (section is! ListFieldSection) {
      return doc;
    }
    final updated = section.copyWith(
      items: [...section.items, const RichTextValue('')],
    );
    return _replaceSection(doc, sectionId, updated);
  }

  /// Updates an item in a list-field section.
  BattleBoxDoc updateListItem(
    BattleBoxDoc doc,
    String sectionId,
    int index,
    String value,
  ) {
    final section = doc.sectionById(sectionId);
    if (section is! ListFieldSection) {
      return doc;
    }
    if (index < 0 || index >= section.items.length) {
      return doc;
    }
    final items = [...section.items];
    items[index] = RichTextValue(value);
    final updated = section.copyWith(items: items);
    return _replaceSection(doc, sectionId, updated);
  }

  /// Deletes an item from a list-field section.
  BattleBoxDoc deleteListItem(BattleBoxDoc doc, String sectionId, int index) {
    final section = doc.sectionById(sectionId);
    if (section is! ListFieldSection) {
      return doc;
    }
    if (index < 0 || index >= section.items.length) {
      return doc;
    }
    final items = [...section.items]..removeAt(index);
    final updated = section.copyWith(items: items);
    return _replaceSection(doc, sectionId, updated);
  }

  /// Updates a cell in a multi-column section.
  BattleBoxDoc updateMultiColumnCell(
    BattleBoxDoc doc,
    String sectionId,
    int columnIndex,
    String value,
  ) {
    final section = doc.sectionById(sectionId);
    if (section is! MultiColumnSection) {
      return doc;
    }
    if (columnIndex < 0 || columnIndex >= section.cells.length) {
      return doc;
    }
    final cells = _copyCells(section.cells);
    cells[columnIndex] = _splitLines(value);
    final updated = section.copyWith(cells: cells);
    return _replaceSection(doc, sectionId, updated);
  }

  /// Adds a new belligerent column to all multi-column sections.
  BattleBoxDoc addBelligerentColumn(BattleBoxDoc doc) {
    final sections = <SectionModel>[];
    for (final section in doc.sections) {
      if (section is MultiColumnSection) {
        final columns = [
          ...section.columns,
          ColumnModel(
            id: _idGenerator.newId(),
            label: 'Belligerent ${section.columns.length + 1}',
          ),
        ];
        final cells = _copyCells(section.cells)
          ..add([const RichTextValue('')]);
        sections.add(section.copyWith(columns: columns, cells: cells));
      } else {
        sections.add(section);
      }
    }
    final updated = doc.copyWith(sections: sections, lastEdited: _clock.now());
    return _clearImportReportIfPresent(updated);
  }

  /// Deletes a belligerent column from all multi-column sections.
  BattleBoxDoc deleteBelligerentColumn(BattleBoxDoc doc, int index) {
    final multiSections = doc.sections.whereType<MultiColumnSection>().toList();
    final firstMulti = multiSections.firstOrNull;
    if (firstMulti == null || firstMulti.columns.length <= 1) {
      return doc;
    }
    if (index < 0 || index >= firstMulti.columns.length) {
      return doc;
    }
    for (final section in multiSections) {
      if (section.columns.length != firstMulti.columns.length) {
        return doc;
      }
      if (index >= section.columns.length || index >= section.cells.length) {
        return doc;
      }
    }

    final sections = <SectionModel>[];
    for (final section in doc.sections) {
      if (section is MultiColumnSection) {
        final columns = [...section.columns]..removeAt(index);
        final cells = _copyCells(section.cells)..removeAt(index);
        sections.add(section.copyWith(columns: columns, cells: cells));
      } else {
        sections.add(section);
      }
    }
    final updated = doc.copyWith(sections: sections, lastEdited: _clock.now());
    return _clearImportReportIfPresent(updated);
  }

  /// Updates the media section.
  BattleBoxDoc setMedia(
    BattleBoxDoc doc, {
    String? imageUrl,
    String? caption,
    String? size,
    String? upright,
  }) {
    final sections = <SectionModel>[];
    for (final section in doc.sections) {
      if (section is MediaSection) {
        sections.add(
          section.copyWith(
            imageUrl: imageUrl,
            caption: caption,
            size: size,
            upright: upright,
          ),
        );
      } else {
        sections.add(section);
      }
    }
    final updated = doc.copyWith(sections: sections, lastEdited: _clock.now());
    return _clearImportReportIfPresent(updated);
  }

  BattleBoxDoc _replaceSection(
    BattleBoxDoc doc,
    String sectionId,
    SectionModel updated,
  ) {
    final sections = [...doc.sections];
    final index = sections.indexWhere((section) => section.id == sectionId);
    if (index == -1) {
      return doc;
    }
    sections[index] = updated;
    final updatedDoc = doc.copyWith(sections: sections, lastEdited: _clock.now());
    return _clearImportReportIfPresent(updatedDoc);
  }

  BattleBoxDoc _clearImportReportIfPresent(BattleBoxDoc doc) {
    if (doc.importReport == null) {
      return doc;
    }
    return doc.copyWith(importReport: null);
  }
}

List<List<RichTextValue>> _copyCells(List<List<RichTextValue>> cells) {
  return cells.map((cell) => [...cell]).toList();
}

List<RichTextValue> _splitLines(String value) {
  final trimmed = value.trimRight();
  if (trimmed.isEmpty) {
    return [const RichTextValue('')];
  }
  final lines = trimmed.split('\n');
  return lines.map((line) => RichTextValue(line)).toList();
}
