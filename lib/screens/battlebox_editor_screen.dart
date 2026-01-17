import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/battlebox_models.dart';
import '../services/image_exporter.dart';
import '../services/wikitext_parser.dart';
import '../state/battlebox_controller.dart';
import '../widgets/battlebox_card.dart';
import '../widgets/wikitext_inline_renderer.dart';

const _wikiSurface = Color(0xFFF8F9FA);
const _wikiBorder = Color(0xFFA2A9B1);
const _wikiText = Color(0xFF202122);
const _wikiSubtleText = Color(0xFF54595D);

class BattleBoxEditorScreen extends ConsumerStatefulWidget {
  const BattleBoxEditorScreen({super.key});

  @override
  ConsumerState<BattleBoxEditorScreen> createState() =>
      _BattleBoxEditorScreenState();
}

class _BattleBoxEditorScreenState extends ConsumerState<BattleBoxEditorScreen> {
  late final TextEditingController _wikitextController;
  final WikitextParser _parser = WikitextParser();
  final GlobalKey _battleBoxKey = GlobalKey();
  bool _showPanel = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    final doc = ref.read(battleBoxProvider);
    _wikitextController = TextEditingController(text: _parser.export(doc));
  }

  @override
  void dispose() {
    _wikitextController.dispose();
    super.dispose();
  }

  void _importWikitext() {
    final doc = _parser.parse(_wikitextController.text);
    ref.read(battleBoxProvider.notifier).replaceDoc(doc);
  }

  void _exportWikitext() {
    final doc = ref.read(battleBoxProvider);
    _wikitextController.text = _parser.export(doc);
  }

  Future<void> _copyWikitext() async {
    await Clipboard.setData(ClipboardData(text: _wikitextController.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wikitext copied to clipboard')),
      );
    }
  }

  void _togglePanel() {
    if (_showPanel) {
      FocusScope.of(context).unfocus();
    }
    setState(() {
      _showPanel = !_showPanel;
    });
  }

  Future<void> _exportImage() async {
    if (_isExporting) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isExporting = true;
    });
    try {
      // Precache all network images before capture
      await _precacheAllImages();

      // Wait for the frame to complete after precaching
      await WidgetsBinding.instance.endOfFrame;

      final boundary =
          _battleBoxKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export failed: card not ready.')),
          );
        }
        return;
      }
      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export failed: could not render PNG.')),
          );
        }
        return;
      }
      final savedPath = await exportPng(
        byteData.buffer.asUint8List(),
        filename: 'battlebox.png',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              savedPath == null
                  ? 'Image download started.'
                  : 'Image saved to $savedPath',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export failed.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _precacheAllImages() async {
    if (!mounted) return;

    final doc = ref.read(battleBoxProvider);
    final resolver = ref.read(wikiIconResolverProvider);
    final dpr = MediaQuery.of(context).devicePixelRatio;

    final imageUrls = <Future<String?>>[];

    // Collect all text content that may contain flag macros
    final allTexts = <String>[];
    allTexts.add(doc.title);

    for (final section in doc.sections) {
      if (!section.isVisible) continue;

      switch (section) {
        case MediaSection section:
          final url = section.imageUrl;
          if (url != null && url.trim().isNotEmpty) {
            // Directly add media URL for precaching
            imageUrls.add(Future.value(url));
          }
          if (section.caption != null) {
            allTexts.add(section.caption!);
          }
        case SingleFieldSection section:
          if (section.value != null) {
            allTexts.add(section.value!.raw);
          }
        case ListFieldSection section:
          for (final item in section.items) {
            allTexts.add(item.raw);
          }
        case MultiColumnSection section:
          for (final column in section.cells) {
            for (final cell in column) {
              allTexts.add(cell.raw);
            }
          }
      }
    }

    // Parse flag macros from all text and resolve their URLs
    final flagMacroPattern = RegExp(r'\{\{([^{}]+)\}\}');
    for (final text in allTexts) {
      for (final match in flagMacroPattern.allMatches(text)) {
        final inner = match.group(1) ?? '';
        final macro = _parseFlagMacro(inner);
        if (macro != null) {
          final fontSize = 14.0;
          final height = fontSize + 2;
          final width = height * 1.4;
          final widthPx = (width * dpr).round();

          imageUrls.add(resolver.resolveFlagIcon(
            templateName: macro.templateName,
            code: macro.code,
            widthPx: widthPx,
            hostOverride: macro.hostOverride,
          ));
        }
      }
    }

    // Resolve all URLs and precache them
    final resolvedUrls = await Future.wait(imageUrls);
    final precacheFutures = <Future<void>>[];

    for (final url in resolvedUrls) {
      if (url != null && url.isNotEmpty && mounted) {
        precacheFutures.add(
          precacheImage(NetworkImage(url), context).catchError((_) {}),
        );
      }
    }

    await Future.wait(precacheFutures);
  }

  _FlagMacro? _parseFlagMacro(String content) {
    final parts = content.split('|').map((p) => p.trim()).toList();
    if (parts.isEmpty) return null;

    final templateName = parts.first;
    final templateKey = templateName.toLowerCase();
    if (templateKey != 'flagicon' && templateKey != 'flag icon') {
      return null;
    }

    String? code;
    String? hostOverride;
    for (var i = 1; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty) continue;

      final eqIndex = part.indexOf('=');
      if (eqIndex != -1) {
        final key = part.substring(0, eqIndex).trim().toLowerCase();
        final value = part.substring(eqIndex + 1).trim();
        if (key == 'host' || key == 'wiki') {
          hostOverride = value;
        }
      } else {
        code ??= part;
      }
    }

    if (code == null || code.isEmpty) return null;

    return _FlagMacro(
      templateName: templateName,
      code: code,
      hostOverride: hostOverride,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 960;
    final showPanel = isWide || _showPanel;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Battlebox Editor'),
        backgroundColor: const Color(0xFFEAECF0),
        foregroundColor: _wikiText,
        elevation: 0,
        actions: [
          if (!isWide)
            IconButton(
              tooltip: showPanel ? 'Collapse wikitext' : 'Expand wikitext',
              icon: Icon(
                showPanel ? Icons.expand_less : Icons.expand_more,
              ),
              onPressed: _togglePanel,
            ),
        ],
      ),
      body: Stack(
        children: [
          _Background(),
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 360,
                              child: WikitextPanel(
                                controller: _wikitextController,
                                onImport: _importWikitext,
                                onExport: _exportWikitext,
                                onCopy: _copyWikitext,
                                onExportImage: _exportImage,
                                isExporting: _isExporting,
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: RepaintBoundary(
                                  key: _battleBoxKey,
                                  child: BattleBoxCard(
                                    isExportMode: _isExporting,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            WikitextPanel(
                              controller: _wikitextController,
                              onImport: _importWikitext,
                              onExport: _exportWikitext,
                              onCopy: _copyWikitext,
                              onExportImage: _exportImage,
                              isExporting: _isExporting,
                              isCollapsible: true,
                              isExpanded: showPanel,
                              onToggle: _togglePanel,
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: RepaintBoundary(
                                key: _battleBoxKey,
                                child: BattleBoxCard(
                                  isExportMode: _isExporting,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class WikitextPanel extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onCopy;
  final VoidCallback onExportImage;
  final bool isExporting;
  final bool isCollapsible;
  final bool isExpanded;
  final VoidCallback? onToggle;

  const WikitextPanel({
    super.key,
    required this.controller,
    required this.onImport,
    required this.onExport,
    required this.onCopy,
    required this.onExportImage,
    this.isExporting = false,
    this.isCollapsible = false,
    this.isExpanded = true,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final bodyVisible = !isCollapsible || isExpanded;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _wikiSurface,
        border: Border.all(color: _wikiBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: isCollapsible ? onToggle : null,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Wikitext',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: _wikiText,
                        ),
                  ),
                ),
                if (isCollapsible)
                  Icon(
                    bodyVisible ? Icons.expand_less : Icons.expand_more,
                    color: _wikiSubtleText,
                  ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  minLines: 12,
                  maxLines: 18,
                  style: const TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 12,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: _wikiBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _wikiBorder),
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onImport,
                      icon: const Icon(Icons.file_download),
                      label: const Text('Import'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onExport,
                      icon: const Icon(Icons.file_upload),
                      label: const Text('Export'),
                    ),
                    OutlinedButton.icon(
                      onPressed: isExporting ? null : onExportImage,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Export Image'),
                    ),
                    FilledButton.icon(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
              ],
            ),
            crossFadeState: bodyVisible
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}

class _Background extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF7F7F7), Color(0xFFECEFF2)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }
}

class _FlagMacro {
  final String templateName;
  final String code;
  final String? hostOverride;

  const _FlagMacro({
    required this.templateName,
    required this.code,
    this.hostOverride,
  });
}
