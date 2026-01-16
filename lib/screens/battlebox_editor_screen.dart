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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 960;
        final showPanel = isWide || _showPanel;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Battlebox Editor'),
            actions: [
              if (!isWide)
                IconButton(
                  tooltip: showPanel ? 'Hide wikitext' : 'Show wikitext',
                  icon: Icon(showPanel ? Icons.code_off : Icons.code),
                  onPressed: () {
                    setState(() {
                      _showPanel = !_showPanel;
                    });
                  },
                ),
            ],
          ),
          body: Stack(
            children: [
              _Background(),
              Padding(
                padding: const EdgeInsets.all(16),
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
                        children: [
                          if (showPanel)
                            WikitextPanel(
                              controller: _wikitextController,
                              onImport: _importWikitext,
                              onExport: _exportWikitext,
                              onCopy: _copyWikitext,
                            ),
                          const SizedBox(height: 16),
                          const Center(child: BattleBoxCard()),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class WikitextPanel extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onCopy;

  const WikitextPanel({
    super.key,
    required this.controller,
    required this.onImport,
    required this.onExport,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
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
          Text(
            'Wikitext',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF5A4733),
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            minLines: 12,
            maxLines: 18,
            style: const TextStyle(fontFamily: 'Courier New', fontSize: 12),
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
