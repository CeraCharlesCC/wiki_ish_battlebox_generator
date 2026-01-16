import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/battlebox_models.dart';
import '../state/battlebox_controller.dart';
import 'editable_value.dart';
import 'wikitext_inline_renderer.dart';

class BattleBoxCard extends ConsumerWidget {
  const BattleBoxCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(battleBoxProvider);
    final controller = ref.read(battleBoxProvider.notifier);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380, minWidth: 320),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          border: Border.all(color: const Color(0xFF8A9AA9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeaderBlock(
              title: doc.title,
              onTitleChanged: controller.setTitle,
            ),
            for (final section in doc.sections)
              if (section.isVisible)
                switch (section) {
                  MediaSection section => _MediaBlock(
                      section: section,
                      onUpdate: controller.setMedia,
                    ),
                  SingleFieldSection section => _SingleFieldRow(
                      section: section,
                      onChanged: controller.setSingleField,
                      onClear: controller.clearSingleField,
                    ),
                  ListFieldSection section => _ListFieldRow(
                      section: section,
                      onAdd: controller.addListItem,
                      onChanged: controller.updateListItem,
                      onDelete: controller.deleteListItem,
                    ),
                  MultiColumnSection section => _MultiColumnBlock(
                      section: section,
                      onAddColumn: controller.addBelligerentColumn,
                      onDeleteColumn: controller.deleteBelligerentColumn,
                      onChanged: controller.updateMultiColumnCell,
                      showAddColumn: section.id == 'combatants',
                    ),
                  _ => const SizedBox.shrink(),
                },
          ],
        ),
      ),
    );
  }
}

class _HeaderBlock extends StatelessWidget {
  final String title;
  final ValueChanged<String> onTitleChanged;

  const _HeaderBlock({
    required this.title,
    required this.onTitleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: const Color(0xFF2F4457),
        child: EditableValue(
          value: title,
          onCommit: onTitleChanged,
          placeholder: 'Conflict title',
          textAlign: TextAlign.center,
          multiline: true,
          displayBuilder: _inlineRenderer,
          textStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
        ),
    );
  }
}

class _MediaBlock extends StatelessWidget {
  final MediaSection section;
  final void Function({
    String? imageUrl,
    String? caption,
    String? size,
    String? upright,
  }) onUpdate;

  const _MediaBlock({
    required this.section,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = section.imageUrl ?? '';
    final hasImage = imageUrl.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFCED7DE))),
        color: Color(0xFFF2F4F7),
      ),
      child: Column(
        children: [
          Container(
            height: 170,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E7EC),
              border: Border.all(color: const Color(0xFFCCD6DD)),
            ),
            child: hasImage
                ? ClipRRect(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (context, error, stackTrace) {
                        return _imagePlaceholder(context);
                      },
                    ),
                  )
                : _imagePlaceholder(context),
          ),
          const SizedBox(height: 6),
          EditableValue(
            value: imageUrl,
            onCommit: (value) => onUpdate(imageUrl: value),
            placeholder: 'Image URL',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          EditableValue(
            value: section.caption ?? '',
            onCommit: (value) => onUpdate(caption: value),
            placeholder: 'Caption',
            textAlign: TextAlign.center,
            multiline: true,
            displayBuilder: _inlineRenderer,
            textStyle: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder(BuildContext context) {
    return Center(
      child: Text(
        'Tap to add image',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: const Color(0xFF556B7D)),
      ),
    );
  }
}

class _SingleFieldRow extends StatelessWidget {
  final SingleFieldSection section;
  final void Function(String sectionId, String value) onChanged;
  final void Function(String sectionId) onClear;

  const _SingleFieldRow({
    required this.section,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final value = section.value?.raw ?? '';
    return _BattleBoxRow(
      label: section.label,
      onAdd: () => onChanged(section.id, ''),
      showAdd: value.trim().isEmpty,
      child: Row(
        children: [
          Expanded(
            child: EditableValue(
              value: value,
              onCommit: (newValue) => onChanged(section.id, newValue),
              placeholder: 'tap to edit',
              multiline: true,
              displayBuilder: _inlineRenderer,
            ),
          ),
          if (value.trim().isNotEmpty)
            _IconButton(
              icon: Icons.delete_outline,
              tooltip: 'Clear',
              onPressed: () => onClear(section.id),
            ),
        ],
      ),
    );
  }
}

class _ListFieldRow extends StatelessWidget {
  final ListFieldSection section;
  final void Function(String sectionId) onAdd;
  final void Function(String sectionId, int index, String value) onChanged;
  final void Function(String sectionId, int index) onDelete;

  const _ListFieldRow({
    required this.section,
    required this.onAdd,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return _BattleBoxRow(
      label: section.label,
      onAdd: () => onAdd(section.id),
      showAdd: true,
      child: Column(
        children: [
          for (var i = 0; i < section.items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: EditableValue(
                      value: section.items[i].raw,
                      onCommit: (value) => onChanged(section.id, i, value),
                      placeholder: 'tap to edit',
                      multiline: true,
                      displayBuilder: _inlineRenderer,
                    ),
                  ),
                  _IconButton(
                    icon: Icons.close,
                    tooltip: 'Delete item',
                    onPressed: () => onDelete(section.id, i),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MultiColumnBlock extends StatelessWidget {
  final MultiColumnSection section;
  final VoidCallback onAddColumn;
  final void Function(int index) onDeleteColumn;
  final void Function(String sectionId, int columnIndex, String value) onChanged;
  final bool showAddColumn;

  const _MultiColumnBlock({
    required this.section,
    required this.onAddColumn,
    required this.onDeleteColumn,
    required this.onChanged,
    required this.showAddColumn,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFCED7DE))),
      ),
      child: Column(
        children: [
          Container(
            color: const Color(0xFF3B5268),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    section.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                if (showAddColumn)
                  _IconButton(
                    icon: Icons.add_circle_outline,
                    tooltip: 'Add belligerent',
                    onPressed: onAddColumn,
                    color: Colors.white,
                  ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < section.columns.length; i++)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: i == section.columns.length - 1
                              ? Colors.transparent
                              : const Color(0xFFCED7DE),
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          color: const Color(0xFFE8EDF2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  section.columns[i].label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              _IconButton(
                                icon: Icons.delete_outline,
                                tooltip: 'Delete column',
                                onPressed: () => onDeleteColumn(i),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: EditableValue(
                            value: section.cells[i].map((e) => e.raw).join('\n'),
                            onCommit: (value) =>
                                onChanged(section.id, i, value),
                            multiline: true,
                            placeholder: 'tap to edit',
                            displayBuilder: _inlineRenderer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BattleBoxRow extends StatelessWidget {
  final String label;
  final VoidCallback onAdd;
  final Widget child;
  final bool showAdd;

  const _BattleBoxRow({
    required this.label,
    required this.onAdd,
    required this.child,
    required this.showAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFCED7DE))),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 120,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFE8EDF2),
                border: Border(
                  right: BorderSide(color: Color(0xFFCED7DE)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  if (showAdd)
                    _IconButton(
                      icon: Icons.add,
                      tooltip: 'Add item',
                      onPressed: onAdd,
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: color ?? const Color(0xFF405364)),
      splashRadius: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
    );
  }
}

Widget _inlineRenderer(
  BuildContext context,
  String value,
  TextStyle? style,
  TextAlign align,
) {
  return WikitextInlineRenderer(
    text: value,
    textStyle: style,
    textAlign: align,
  );
}
