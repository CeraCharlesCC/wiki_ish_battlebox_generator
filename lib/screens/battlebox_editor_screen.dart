import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/wikitext_parser.dart';
import '../state/battlebox_controller.dart';
import '../widgets/battlebox_card.dart';

class BattleBoxEditorScreen extends ConsumerStatefulWidget {
  const BattleBoxEditorScreen({super.key});

  @override
  ConsumerState<BattleBoxEditorScreen> createState() =>
      _BattleBoxEditorScreenState();
}

class _BattleBoxEditorScreenState extends ConsumerState<BattleBoxEditorScreen> {
  late final TextEditingController _wikitextController;
  final WikitextParser _parser = WikitextParser();
  bool _showPanel = true;

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

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 960;
    final showPanel = isWide || _showPanel;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Battlebox Editor'),
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
                              ),
                            ),
                            const SizedBox(width: 24),
                            const Expanded(
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: BattleBoxCard(),
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
                              isCollapsible: true,
                              isExpanded: showPanel,
                              onToggle: _togglePanel,
                            ),
                            const SizedBox(height: 16),
                            const Center(child: BattleBoxCard()),
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
  final bool isCollapsible;
  final bool isExpanded;
  final VoidCallback? onToggle;

  const WikitextPanel({
    super.key,
    required this.controller,
    required this.onImport,
    required this.onExport,
    required this.onCopy,
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
        color: const Color(0xFFFDF8F2),
        border: Border.all(color: const Color(0xFFDAC9B8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
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
                          color: const Color(0xFF5A4733),
                        ),
                  ),
                ),
                if (isCollapsible)
                  Icon(
                    bodyVisible ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF5A4733),
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
                    border: OutlineInputBorder(),
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
          colors: [Color(0xFFFDF3E7), Color(0xFFE7EEF7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -80,
            top: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: const Color(0xFFEFDFC8).withOpacity(0.7),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -40,
            bottom: -60,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: const Color(0xFFDDE7F3).withOpacity(0.8),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
