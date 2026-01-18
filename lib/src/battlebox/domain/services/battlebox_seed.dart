import '../../../core/id_generator.dart';
import '../entities/battlebox_doc.dart';
import '../entities/column_model.dart';
import '../entities/rich_text_value.dart';
import '../entities/sections.dart';

/// Factory for creating seed (default) battlebox documents.
class BattleboxSeed {
  final IdGenerator _idGenerator;

  const BattleboxSeed(this._idGenerator);

  /// Creates a new battlebox document with default sections.
  BattleBoxDoc create() {
    final columns = [
      ColumnModel(id: _idGenerator.newId(), label: 'Belligerent 1'),
      ColumnModel(id: _idGenerator.newId(), label: 'Belligerent 2'),
    ];

    return BattleBoxDoc(
      id: _idGenerator.newId(),
      title: 'Battle of Exampleville',
      sections: [
        const MediaSection(id: 'media', label: 'Media'),
        const SingleFieldSection(id: 'partof', label: 'Part of'),
        const ListFieldSection(
          id: 'date',
          label: 'Date',
          items: [RichTextValue('')],
        ),
        const ListFieldSection(
          id: 'location',
          label: 'Location',
          items: [RichTextValue('')],
        ),
        const SingleFieldSection(id: 'coordinates', label: 'Coordinates'),
        const SingleFieldSection(id: 'result', label: 'Result'),
        const SingleFieldSection(
          id: 'territory',
          label: 'Territorial changes',
        ),
        MultiColumnSection(
          id: 'combatants',
          label: 'Combatants',
          columns: columns,
          cells: _buildEmptyCells(columns.length),
        ),
        MultiColumnSection(
          id: 'commanders',
          label: 'Commanders and leaders',
          columns: columns,
          cells: _buildEmptyCells(columns.length),
        ),
        MultiColumnSection(
          id: 'units',
          label: 'Units',
          columns: columns,
          cells: _buildEmptyCells(columns.length),
        ),
        MultiColumnSection(
          id: 'strength',
          label: 'Strength',
          columns: columns,
          cells: _buildEmptyCells(columns.length),
        ),
        MultiColumnSection(
          id: 'casualties',
          label: 'Casualties',
          columns: columns,
          cells: _buildEmptyCells(columns.length),
        ),
      ],
    );
  }

  List<List<RichTextValue>> _buildEmptyCells(int count) {
    return List<List<RichTextValue>>.generate(
      count,
      (_) => [const RichTextValue('')],
    );
  }
}
