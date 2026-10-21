import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/usecases/compute_precache_requests.dart';
import '../../domain/entities/battlebox_doc.dart';
import '../../domain/entities/wikitext_import_report.dart';
import '../state/providers.dart';
import '../widgets/battlebox_card.dart';

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
  final GlobalKey _battleBoxKey = GlobalKey();
  bool _showPanel = true;
  bool _isExporting = false;
  bool _isApplyingImport = false;
  bool _isManualDraft = false;
  bool _visualChangedDuringDraft = false;
  bool _draftRecoveryFailed = false;
  bool _autosaveFailed = false;
  late String _lastSyncedWikitext;
  Timer? _autosaveTimer;

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(battleboxEditorNotifierProvider.notifier);
    _lastSyncedWikitext = notifier.exportWikitext();
    _wikitextController = TextEditingController(text: _lastSyncedWikitext);
    _wikitextController.addListener(_onWikitextEdited);
    // Riverpod cannot notify widgets of document changes while the tree is
    // mounting. Apply local recovery after the initial frame instead.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _isApplyingImport = true;
      _wikitextController.removeListener(_onWikitextEdited);
      try {
        _restoreDraft();
      } finally {
        _wikitextController.addListener(_onWikitextEdited);
        _isApplyingImport = false;
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _persistDraft(notifyUi: false);
    _wikitextController.removeListener(_onWikitextEdited);
    _wikitextController.dispose();
    super.dispose();
  }

  void _restoreDraft() {
    try {
      final saved = ref.read(editorDraftStorageProvider).read();
      if (saved == null) return;
      final decoded = jsonDecode(saved);
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        return;
      }

      final savedDocument = decoded['documentWikitext'];
      var visualRecovered = false;
      if (savedDocument is String && savedDocument.isNotEmpty) {
        try {
          ref
              .read(battleboxEditorNotifierProvider.notifier)
              .restoreWikitext(savedDocument);
          visualRecovered = true;
        } catch (_) {
          // The saved visual document cannot be restored, but the user's raw
          // text is still recoverable in the editor below.
        }
      }
      final rawText = decoded['editorWikitext'];
      final restoredText = decoded['syncedWikitext'];
      _lastSyncedWikitext = restoredText is String
          ? restoredText
          : ref.read(battleboxEditorNotifierProvider.notifier).exportWikitext();
      if (rawText is String) {
        _wikitextController.text = rawText;
        _isManualDraft =
            decoded['manualDraft'] == true ||
            rawText != _lastSyncedWikitext ||
            (!visualRecovered && rawText.isNotEmpty);
        _draftRecoveryFailed = !visualRecovered && rawText.isNotEmpty;
        _visualChangedDuringDraft =
            decoded['visualChangedDuringDraft'] == true || _draftRecoveryFailed;
      } else {
        _wikitextController.text = _lastSyncedWikitext;
      }
    } catch (_) {
      // Invalid JSON or blocked localStorage must not prevent editing.
      _autosaveFailed = true;
    }
  }

  void _setSyncedWikitext(String text) {
    _lastSyncedWikitext = text;
    _isManualDraft = false;
    _visualChangedDuringDraft = false;
    _draftRecoveryFailed = false;
    _wikitextController.removeListener(_onWikitextEdited);
    _wikitextController.text = text;
    _wikitextController.addListener(_onWikitextEdited);
    _scheduleAutosave();
    if (mounted) setState(() {});
  }

  void _onWikitextEdited() {
    final dirty = _wikitextController.text != _lastSyncedWikitext;
    if (!dirty && _visualChangedDuringDraft) {
      _setSyncedWikitext(
        ref.read(battleboxEditorNotifierProvider.notifier).exportWikitext(),
      );
      return;
    }
    if (_isManualDraft != dirty) {
      setState(() => _isManualDraft = dirty);
    }
    _scheduleAutosave();
  }

  void _onDocumentChanged() {
    if (_isApplyingImport) return;
    if (_isManualDraft) {
      setState(() => _visualChangedDuringDraft = true);
      _scheduleAutosave();
    } else {
      _setSyncedWikitext(
        ref.read(battleboxEditorNotifierProvider.notifier).exportWikitext(),
      );
    }
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 300), _persistDraft);
  }

  void _persistDraft({bool notifyUi = true}) {
    try {
      final documentText = ref
          .read(battleboxEditorNotifierProvider.notifier)
          .exportWikitext();
      ref
          .read(editorDraftStorageProvider)
          .write(
            jsonEncode({
              'version': 1,
              'documentWikitext': documentText,
              'editorWikitext': _wikitextController.text,
              'syncedWikitext': _lastSyncedWikitext,
              'manualDraft': _isManualDraft,
              'visualChangedDuringDraft': _visualChangedDuringDraft,
            }),
          );
      if (notifyUi && _autosaveFailed && mounted) {
        setState(() => _autosaveFailed = false);
      }
    } catch (_) {
      if (notifyUi && !_autosaveFailed && mounted) {
        setState(() => _autosaveFailed = true);
      }
    }
  }

  void _importWikitext() {
    final source = _wikitextController.text;
    _isApplyingImport = true;
    try {
      ref.read(battleboxEditorNotifierProvider.notifier).importWikitext(source);
      // Keep the user's exact imported wikitext until the visual editor
      // changes. Regeneration can normalize or omit unsupported markup.
      _setSyncedWikitext(source);
      final report = ref.read(battleboxEditorNotifierProvider).importReport;
      if (report != null && (report.partialCount + report.failedCount) > 0) {
        _showMessage(
          'Imported with warnings. Review the import report before exporting.',
        );
      }
    } on FormatException catch (error) {
      _showMessage(
        'Import rejected; your document is unchanged. ${error.message}',
      );
    } catch (error) {
      _showMessage('Import failed; your document is unchanged: $error');
    } finally {
      _isApplyingImport = false;
    }
  }

  Future<void> _exportWikitext() async {
    if (_isManualDraft) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Replace your wikitext draft?'),
          content: const Text(
            'This will overwrite your unimported wikitext edits with the current visual editor contents.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep draft'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Replace from visual'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    final wikitext = ref
        .read(battleboxEditorNotifierProvider.notifier)
        .exportWikitext();
    _setSyncedWikitext(wikitext);
  }

  Future<void> _copyWikitext() async {
    // When no visual edits followed an import, the original source is safer
    // than a fresh serialization: it may contain unsupported wiki markup.
    var text = _wikitextController.text;
    if (_isManualDraft && _visualChangedDuringDraft) {
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Two versions of wikitext'),
          content: const Text(
            'Both the visual editor and your unimported wikitext draft have changed. Choose which version to copy.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'draft'),
              child: const Text('Copy my draft'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'visual'),
              child: const Text('Copy visual editor'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'visual') {
        text = ref
            .read(battleboxEditorNotifierProvider.notifier)
            .exportWikitext();
      }
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _showMessage('Wikitext copied to clipboard.');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      // A broken MediaWiki icon must not block the rest of the PNG export.
      final failedImages = await _precacheAllImages();

      // Give widgets (FutureBuilders/Image decoders) a chance to rebuild/paint
      // with the now-cached URLs and decoded images before we snapshot.
      if (mounted) {
        setState(() {});
      }
      await WidgetsBinding.instance.endOfFrame;
      // One extra frame makes the export far more reliable for inline WidgetSpans.
      await WidgetsBinding.instance.endOfFrame;

      final boundary =
          _battleBoxKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export failed: card not ready.')),
          );
        }
        return;
      }
      if (!mounted) {
        return;
      }
      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      ByteData? byteData;
      try {
        byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        image.dispose();
      }
      if (byteData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Export failed: could not render PNG.'),
            ),
          );
        }
        return;
      }
      final exporter = ref.read(imageExporterProvider);
      final savedPath = await exporter.exportPng(
        byteData.buffer.asUint8List(),
        filename: 'battlebox.png',
      );
      if (mounted) {
        _showMessage(
          '${savedPath == null ? 'Image download started.' : 'Image saved to $savedPath'}'
          '${failedImages > 0 ? ' ($failedImages image(s) unavailable; placeholders used)' : ''}',
        );
      }
    } catch (error) {
      final reason = error.toString();
      _showMessage(
        'PNG export failed: ${reason.length > 180 ? reason.substring(0, 180) : reason}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  List<double> _candidateFontSizes(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sizes = <double?>[
      t.titleMedium?.fontSize,
      t.titleSmall?.fontSize,
      t.bodyMedium?.fontSize,
      t.bodySmall?.fontSize,
    ].whereType<double>().where((s) => s > 0).toSet().toList();

    // Fallback for any custom styling / null fontSizes.
    if (!sizes.contains(14.0)) sizes.add(14.0);

    // Small-to-large ordering (not required, but nice for determinism)
    sizes.sort();
    return sizes;
  }

  Future<int> _precacheAllImages() async {
    if (!mounted) return 0;

    final doc = ref.read(battleboxEditorNotifierProvider);
    final gateway = ref.read(wikiIconGatewayProvider);
    final mediaGateway = ref.read(wikiImageGatewayProvider);
    final computePrecache = ref.read(computePrecacheRequestsProvider);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final fontSizes = _candidateFontSizes(context);

    final requests = computePrecache(
      doc: doc,
      fontSizes: fontSizes,
      devicePixelRatio: dpr,
    );

    var failed = 0;

    Future<String?> safelyResolve(Future<String?> Function() resolve) async {
      try {
        final url = await resolve().timeout(const Duration(seconds: 10));
        if (url == null || url.isEmpty) failed++;
        return url;
      } catch (_) {
        failed++;
        return null;
      }
    }

    final imageUrls = <Future<String?>>[];
    for (final request in requests) {
      switch (request) {
        case DirectUrlRequest request:
          imageUrls.add(
            safelyResolve(() => mediaGateway.resolveImageUrl(request.url)),
          );
        case FlagIconRequest request:
          imageUrls.add(
            safelyResolve(
              () => gateway.resolveFlagIcon(
                templateName: request.templateName,
                code: request.code,
                widthPx: request.widthPx,
                hostOverride: request.hostOverride,
              ),
            ),
          );
      }
    }

    // Resolve all URLs and precache them
    final resolvedUrls = await Future.wait(imageUrls);
    final precacheFutures = <Future<void>>[];

    for (final url in resolvedUrls.toSet()) {
      if (url != null && url.isNotEmpty && mounted) {
        precacheFutures.add(
          precacheImage(
            NetworkImage(url),
            context,
          ).timeout(const Duration(seconds: 10)).catchError((Object _) {
            failed++;
          }),
        );
      }
    }

    await Future.wait(precacheFutures);
    return failed;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(battleboxEditorNotifierProvider);
    ref.listen<BattleBoxDoc>(
      battleboxEditorNotifierProvider,
      (previous, next) => _onDocumentChanged(),
    );
    final notifier = ref.read(battleboxEditorNotifierProvider.notifier);
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
              icon: Icon(showPanel ? Icons.expand_less : Icons.expand_more),
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
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
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
                                onUndo: notifier.undo,
                                onRedo: notifier.redo,
                                canUndo: notifier.canUndo,
                                canRedo: notifier.canRedo,
                                hasManualDraft: _isManualDraft,
                                hasConflictingEdits: _visualChangedDuringDraft,
                                autosaveFailed: _autosaveFailed,
                                recoveryFailed: _draftRecoveryFailed,
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: RepaintBoundary(
                                    key: _battleBoxKey,
                                    child: BattleBoxCard(
                                      isExportMode: _isExporting,
                                    ),
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
                              onUndo: notifier.undo,
                              onRedo: notifier.redo,
                              canUndo: notifier.canUndo,
                              canRedo: notifier.canRedo,
                              hasManualDraft: _isManualDraft,
                              hasConflictingEdits: _visualChangedDuringDraft,
                              autosaveFailed: _autosaveFailed,
                              recoveryFailed: _draftRecoveryFailed,
                              isCollapsible: true,
                              isExpanded: showPanel,
                              onToggle: _togglePanel,
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: RepaintBoundary(
                                  key: _battleBoxKey,
                                  child: BattleBoxCard(
                                    isExportMode: _isExporting,
                                  ),
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

class WikitextPanel extends ConsumerWidget {
  final TextEditingController controller;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onCopy;
  final VoidCallback onExportImage;
  final bool isExporting;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool canUndo;
  final bool canRedo;
  final bool hasManualDraft;
  final bool hasConflictingEdits;
  final bool autosaveFailed;
  final bool recoveryFailed;
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
    this.onUndo,
    this.onRedo,
    this.canUndo = false,
    this.canRedo = false,
    this.hasManualDraft = false,
    this.hasConflictingEdits = false,
    this.autosaveFailed = false,
    this.recoveryFailed = false,
    this.isCollapsible = false,
    this.isExpanded = true,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bodyVisible = !isCollapsible || isExpanded;
    final report = ref.watch(battleboxEditorNotifierProvider).importReport;
    final reportFields =
        report?.fields.values.toList() ?? const <ImportFieldReport>[];
    final flaggedFields =
        reportFields
            .where(
              (field) =>
                  field.status == ImportFieldStatus.partial ||
                  field.status == ImportFieldStatus.failed,
            )
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final fieldsWithFragments =
        reportFields
            .where((field) => field.unparsedFragments.isNotEmpty)
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));

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
                IconButton(
                  tooltip: 'Undo visual edit',
                  onPressed: canUndo ? onUndo : null,
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: 'Redo visual edit',
                  onPressed: canRedo ? onRedo : null,
                  icon: const Icon(Icons.redo),
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
                if (hasManualDraft) ...[
                  if (recoveryFailed) ...[
                    Text(
                      'The saved visual document could not be restored. Your original wikitext remains below; Import it to recover, or Copy it before editing further.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFB32424),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    hasConflictingEdits
                        ? 'Unimported wikitext and visual changes conflict. Import your draft, or use Export to replace it. Copy will ask which version to use.'
                        : 'Unimported wikitext draft. Visual edits will not overwrite it.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF8B5300),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  autosaveFailed
                      ? 'Local autosave unavailable in this browser. Copy your work before leaving.'
                      : 'Draft autosaves locally in this browser.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: autosaveFailed
                        ? const Color(0xFFB32424)
                        : _wikiSubtleText,
                  ),
                ),
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
                      icon: isExporting
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.image_outlined),
                      label: Text(
                        isExporting ? 'Exporting...' : 'Export Image',
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
                if (report != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Import report',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _wikiText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Parsed: ${report.parsedCount} • Partial: ${report.partialCount} • Failed: ${report.failedCount}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: _wikiSubtleText),
                  ),
                  if (flaggedFields.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final field in flaggedFields)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '${field.key}: ${field.status.name}${field.firstOffendingToken == null ? '' : ' • ${field.firstOffendingToken}'}',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: _wikiText),
                        ),
                      ),
                  ],
                  if (fieldsWithFragments.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Unparsed fragments',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _wikiText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final field in fieldsWithFragments)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              field.key,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: _wikiSubtleText,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            for (final fragment in field.unparsedFragments)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  border: Border.all(color: _wikiBorder),
                                ),
                                child: SelectableText(
                                  fragment,
                                  style: const TextStyle(
                                    fontFamily: 'Courier New',
                                    fontSize: 11,
                                    color: _wikiText,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
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
