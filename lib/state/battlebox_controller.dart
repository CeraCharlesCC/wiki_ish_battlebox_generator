import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/battlebox_models.dart';

final battleBoxProvider =
    StateNotifierProvider<BattleBoxController, BattleBoxDoc>(
  (ref) => BattleBoxController(),
);

class BattleBoxController extends StateNotifier<BattleBoxDoc> {
  BattleBoxController() : super(BattleBoxDoc.seed());

  void replaceDoc(BattleBoxDoc doc) {
    state = doc.copyWith(lastEdited: DateTime.now());
  }

  void setTitle(String value) {
    state = state.copyWith(title: value, lastEdited: DateTime.now());
  }

  void setSingleField(String sectionId, String value) {
    final section = state.sectionById(sectionId);
    if (section is! SingleFieldSection) {
      return;
    }
    final updated = section.copyWith(value: RichTextValue(value));
    _replaceSection(sectionId, updated);
  }

  void clearSingleField(String sectionId) {
    final section = state.sectionById(sectionId);
    if (section is! SingleFieldSection) {
      return;
    }
    final updated = section.copyWith(value: const RichTextValue(''));
    _replaceSection(sectionId, updated);
  }

  void addListItem(String sectionId) {
    final section = state.sectionById(sectionId);
    if (section is! ListFieldSection) {
      return;
    }
    final updated = section.copyWith(
      items: [...section.items, const RichTextValue('')],
    );
    _replaceSection(sectionId, updated);
  }

  void updateListItem(String sectionId, int index, String value) {
    final section = state.sectionById(sectionId);
    if (section is! ListFieldSection) {
      return;
    }
    if (index < 0 || index >= section.items.length) {
      return;
    }
    final items = [...section.items];
    items[index] = RichTextValue(value);
    final updated = section.copyWith(items: items);
    _replaceSection(sectionId, updated);
  }

  void deleteListItem(String sectionId, int index) {
    final section = state.sectionById(sectionId);
    if (section is! ListFieldSection) {
      return;
    }
    if (index < 0 || index >= section.items.length) {
      return;
    }
    final items = [...section.items]..removeAt(index);
    final updated = section.copyWith(items: items);
    _replaceSection(sectionId, updated);
  }

  void updateMultiColumnCell(
    String sectionId,
    int columnIndex,
    String value,
  ) {
    final section = state.sectionById(sectionId);
    if (section is! MultiColumnSection) {
      return;
    }
    if (columnIndex < 0 || columnIndex >= section.cells.length) {
      return;
    }
    final cells = _copyCells(section.cells);
    cells[columnIndex] = _splitLines(value);
    final updated = section.copyWith(cells: cells);
    _replaceSection(sectionId, updated);
  }

  void addBelligerentColumn() {
    final sections = <SectionModel>[];
    for (final section in state.sections) {
      if (section is MultiColumnSection) {
        final columns = [...section.columns]
          ..add(
            ColumnModel(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              label: 'Belligerent ${section.columns.length + 1}',
            ),
          );
        final cells = _copyCells(section.cells)
          ..add([const RichTextValue('')]);
        sections.add(section.copyWith(columns: columns, cells: cells));
      } else {
        sections.add(section);
      }
    }
    state = state.copyWith(sections: sections, lastEdited: DateTime.now());
  }

  void deleteBelligerentColumn(int index) {
    final firstMulti = state.sections.whereType<MultiColumnSection>().firstOrNull;
    if (firstMulti == null || firstMulti.columns.length <= 1) {
      return;
    }
    final sections = <SectionModel>[];
    for (final section in state.sections) {
      if (section is MultiColumnSection) {
        if (index < 0 || index >= section.columns.length) {
          sections.add(section);
          continue;
        }
        final columns = [...section.columns]..removeAt(index);
        final cells = _copyCells(section.cells)..removeAt(index);
        sections.add(section.copyWith(columns: columns, cells: cells));
      } else {
        sections.add(section);
      }
    }
    state = state.copyWith(sections: sections, lastEdited: DateTime.now());
  }

  void setMedia({
    String? imageUrl,
    String? caption,
    String? size,
    String? upright,
  }) {
    final sections = <SectionModel>[];
    for (final section in state.sections) {
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
    state = state.copyWith(sections: sections, lastEdited: DateTime.now());
  }

  void _replaceSection(String sectionId, SectionModel updated) {
    final sections = [...state.sections];
    final index = sections.indexWhere((section) => section.id == sectionId);
    if (index == -1) {
      return;
    }
    sections[index] = updated;
    state = state.copyWith(sections: sections, lastEdited: DateTime.now());
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

extension _IterableExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
