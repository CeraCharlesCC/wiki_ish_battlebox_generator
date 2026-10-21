import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/sections.dart';
import '../state/providers.dart';
import 'editable_value.dart';
import 'wikitext_inline_renderer.dart';

const _infoboxBorder = Color(0xFFA2A9B1);
const _infoboxBackground = Color(0xFFF8F9FA);
const _infoboxHeaderBackground = Color(0xFFD8E4F2);
const _infoboxLabelBackground = Color(0xFFEAECF0);
const _infoboxColumnHeaderBackground = Color(0xFFF2F4F7);
const _infoboxIconColor = Color(0xFF54595D);
const _defaultCardWidth = 380.0;
const _minimumColumnWidth = 112.0;

class BattleBoxCard extends ConsumerWidget {
  final bool isExportMode;

  const BattleBoxCard({super.key, this.isExportMode = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(battleboxEditorNotifierProvider);
    final controller = ref.read(battleboxEditorNotifierProvider.notifier);

    // RepaintBoundary.toImage uses the card's *rendered* width. During export,
    // let that width accommodate every visible column instead of capturing
    // only the first 380 px of a horizontally scrolled section.
    var exportColumns = 0;
    if (isExportMode) {
      for (final section in doc.sections) {
        if (section is MultiColumnSection &&
            section.isVisible &&
            !_isSectionEmpty(section)) {
          exportColumns = math.max(exportColumns, section.columns.length);
        }
      }
    }
    final exportWidth = math.max(
      _defaultCardWidth,
      exportColumns * _minimumColumnWidth + 2, // Card's left and right borders.
    );

    return ConstrainedBox(
      constraints: isExportMode
          ? BoxConstraints.tightFor(width: exportWidth)
          : const BoxConstraints(minWidth: 320, maxWidth: _defaultCardWidth),
      child: Container(
        decoration: BoxDecoration(
          color: _infoboxBackground,
          border: Border.all(color: _infoboxBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeaderBlock(
              title: doc.title,
              onTitleChanged: controller.setTitle,
              isExportMode: isExportMode,
            ),
            for (final section in doc.sections)
              if (section.isVisible &&
                  (!isExportMode || !_isSectionEmpty(section)))
                switch (section) {
                  MediaSection section => _MediaBlock(
                    section: section,
                    onUpdate: controller.setMedia,
                    isExportMode: isExportMode,
                  ),
                  SingleFieldSection section => _SingleFieldRow(
                    section: section,
                    onChanged: controller.setSingleField,
                    onClear: controller.clearSingleField,
                    isExportMode: isExportMode,
                  ),
                  ListFieldSection section => _ListFieldRow(
                    section: section,
                    onAdd: controller.addListItem,
                    onChanged: controller.updateListItem,
                    onDelete: controller.deleteListItem,
                    isExportMode: isExportMode,
                  ),
                  MultiColumnSection section => _MultiColumnBlock(
                    section: section,
                    onAddColumn: controller.addBelligerentColumn,
                    onDeleteColumn: controller.deleteBelligerentColumn,
                    onChanged: controller.updateMultiColumnCell,
                    showAddColumn: section.id == 'combatants',
                    isExportMode: isExportMode,
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
  final bool isExportMode;

  const _HeaderBlock({
    required this.title,
    required this.onTitleChanged,
    required this.isExportMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: _infoboxHeaderBackground,
        border: Border(bottom: BorderSide(color: _infoboxBorder)),
      ),
      child: EditableValue(
        value: title,
        onCommit: onTitleChanged,
        placeholder: 'Conflict title',
        textAlign: TextAlign.center,
        multiline: true,
        displayBuilder: _inlineRenderer,
        isReadOnly: isExportMode,
        showPlaceholderWhenEmpty: !isExportMode,
        textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: const Color(0xFF202122),
          fontWeight: FontWeight.w700,
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
  })
  onUpdate;
  final bool isExportMode;

  const _MediaBlock({
    required this.section,
    required this.onUpdate,
    required this.isExportMode,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = section.imageUrl ?? '';
    final hasImage = imageUrl.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _infoboxBorder)),
        color: _infoboxBackground,
      ),
      child: Column(
        children: [
          Container(
            height: 170,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _infoboxBorder),
            ),
            child: hasImage
                ? _ResolvedMediaImage(
                    source: imageUrl,
                    isExportMode: isExportMode,
                  )
                : _imagePlaceholder(context, showText: !isExportMode),
          ),
          const SizedBox(height: 6),
          if (!isExportMode) ...[
            EditableValue(
              value: imageUrl,
              onCommit: (value) => onUpdate(imageUrl: value),
              placeholder: 'Wikipedia image filename or URL',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
          ],
          EditableValue(
            value: section.caption ?? '',
            onCommit: (value) => onUpdate(caption: value),
            placeholder: 'Caption',
            textAlign: TextAlign.center,
            multiline: true,
            displayBuilder: _inlineRenderer,
            isReadOnly: isExportMode,
            showPlaceholderWhenEmpty: !isExportMode,
            textStyle: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder(BuildContext context, {required bool showText}) {
    if (!showText) {
      return const SizedBox.expand();
    }
    return Center(
      child: Text(
        'Tap to add image',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6C7278)),
      ),
    );
  }
}

/// The resolved URL is retained across rebuilds; otherwise a FutureBuilder
/// could briefly show a blank image every time a visual field changes.
class _ResolvedMediaImage extends ConsumerStatefulWidget {
  final String source;
  final bool isExportMode;

  const _ResolvedMediaImage({required this.source, required this.isExportMode});

  @override
  ConsumerState<_ResolvedMediaImage> createState() =>
      _ResolvedMediaImageState();
}

class _ResolvedMediaImageState extends ConsumerState<_ResolvedMediaImage> {
  late Future<String?> _imageUrl;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_ResolvedMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _resolve();
  }

  void _resolve() {
    _imageUrl = ref
        .read(wikiImageGatewayProvider)
        .resolveImageUrl(widget.source);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _imageUrl,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null || url.isEmpty) {
          if (!widget.isExportMode &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          return widget.isExportMode
              ? const SizedBox.expand()
              : const Center(child: Text('Image unavailable'));
        }
        return Image.network(
          url,
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (context, error, stackTrace) => widget.isExportMode
              ? const SizedBox.expand()
              : const Center(child: Text('Could not load image')),
        );
      },
    );
  }
}

class _SingleFieldRow extends StatelessWidget {
  final SingleFieldSection section;
  final void Function(String sectionId, String value) onChanged;
  final void Function(String sectionId) onClear;
  final bool isExportMode;

  const _SingleFieldRow({
    required this.section,
    required this.onChanged,
    required this.onClear,
    required this.isExportMode,
  });

  @override
  Widget build(BuildContext context) {
    final value = section.value?.raw ?? '';
    return _BattleBoxRow(
      label: section.label,
      onAdd: () => onChanged(section.id, ''),
      showAdd: !isExportMode && value.trim().isEmpty,
      child: Row(
        children: [
          Expanded(
            child: EditableValue(
              value: value,
              onCommit: (newValue) => onChanged(section.id, newValue),
              placeholder: 'tap to edit',
              multiline: true,
              displayBuilder: _inlineRenderer,
              isReadOnly: isExportMode,
              showPlaceholderWhenEmpty: !isExportMode,
            ),
          ),
          if (!isExportMode && value.trim().isNotEmpty)
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
  final bool isExportMode;

  const _ListFieldRow({
    required this.section,
    required this.onAdd,
    required this.onChanged,
    required this.onDelete,
    required this.isExportMode,
  });

  @override
  Widget build(BuildContext context) {
    return _BattleBoxRow(
      label: section.label,
      onAdd: () => onAdd(section.id),
      showAdd: !isExportMode,
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
                      isReadOnly: isExportMode,
                      showPlaceholderWhenEmpty: !isExportMode,
                    ),
                  ),
                  if (!isExportMode)
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
  final void Function(String sectionId, int columnIndex, String value)
  onChanged;
  final bool showAddColumn;
  final bool isExportMode;

  const _MultiColumnBlock({
    required this.section,
    required this.onAddColumn,
    required this.onDeleteColumn,
    required this.onChanged,
    required this.showAddColumn,
    required this.isExportMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _infoboxBorder)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: _infoboxHeaderBackground,
              border: Border(bottom: BorderSide(color: _infoboxBorder)),
            ),
            child: SizedBox(
              height: 24,
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      section.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF202122),
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (showAddColumn && !isExportMode)
                    Align(
                      alignment: Alignment.centerRight,
                      child: _IconButton(
                        icon: Icons.add_circle_outline,
                        tooltip: 'Add belligerent',
                        onPressed: onAddColumn,
                      ),
                    ),
                ],
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final content = SizedBox(
                width: math.max(
                  section.columns.length * _minimumColumnWidth,
                  constraints.maxWidth,
                ),
                child: Row(
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
                                    : _infoboxBorder,
                              ),
                            ),
                          ),
                          child: Column(
                            children: [
                              if (!isExportMode)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  color: _infoboxColumnHeaderBackground,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          section.columns[i].label,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: const Color(0xFF202122),
                                              ),
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
                                  value: section.cells[i]
                                      .map((e) => e.raw)
                                      .join('\n'),
                                  onCommit: (value) =>
                                      onChanged(section.id, i, value),
                                  multiline: true,
                                  placeholder: 'tap to edit',
                                  displayBuilder: _inlineRenderer,
                                  isReadOnly: isExportMode,
                                  showPlaceholderWhenEmpty: !isExportMode,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
              // Editing can scroll individual sections; exports must paint the
              // complete row onto the card's expanded capture surface.
              return isExportMode
                  ? content
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: content,
                    );
            },
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
        border: Border(bottom: BorderSide(color: _infoboxBorder)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: (constraints.maxWidth * 0.36)
                    .clamp(80.0, 120.0)
                    .toDouble(),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: const BoxDecoration(
                  color: _infoboxLabelBackground,
                  border: Border(right: BorderSide(color: _infoboxBorder)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF202122),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: _infoboxIconColor),
      splashRadius: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
    );
  }
}

bool _isSectionEmpty(SectionModel section) {
  return switch (section) {
    MediaSection s =>
      (s.imageUrl?.trim().isEmpty ?? true) &&
          (s.caption?.trim().isEmpty ?? true),
    SingleFieldSection s => s.value?.isEmpty ?? true,
    ListFieldSection s =>
      s.items.isEmpty || s.items.every((item) => item.isEmpty),
    MultiColumnSection s => s.cells.every(
      (column) => column.every((cell) => cell.isEmpty),
    ),
    _ => false,
  };
}

Widget _inlineRenderer(
  BuildContext context,
  String value,
  TextStyle? style,
  TextAlign align,
  bool isInteractive,
) {
  return WikitextInlineRenderer(
    text: value,
    textStyle: style,
    textAlign: align,
    isInteractive: isInteractive,
  );
}
