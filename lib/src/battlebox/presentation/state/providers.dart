import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/clock.dart';
import '../../../core/id_generator.dart';
import '../../application/ports/battlebox_serializer.dart';
import '../../application/ports/external_link_opener.dart';
import '../../application/ports/image_exporter.dart';
import '../../application/ports/wiki_icon_gateway.dart';
import '../../application/ports/wiki_link_gateway.dart';
import '../../application/usecases/battlebox_editing_usecases.dart';
import '../../application/usecases/compute_precache_requests.dart';
import '../../application/usecases/export_wikitext.dart';
import '../../application/usecases/import_wikitext.dart';
import '../../domain/entities/battlebox_doc.dart';
import '../../domain/services/battlebox_editor.dart';
import '../../domain/services/battlebox_seed.dart';
import '../../infrastructure/http/wiki_icon_mediawiki_adapter.dart';
import '../../infrastructure/http/wiki_link_mediawiki_adapter.dart';
import '../../infrastructure/platform/platform_image_exporter.dart';
import '../../infrastructure/serialization/wikitext_battlebox_serializer.dart';
import '../../infrastructure/system/url_launcher_opener.dart';
import 'battlebox_editor_notifier.dart';
import '../../../../services/wikitext_inline_parser.dart';

/// Provides the shared HTTP client for all network operations.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Provides the WikiIconGateway port implementation.
final wikiIconGatewayProvider = Provider<WikiIconGateway>((ref) {
  final client = ref.watch(httpClientProvider);
  final adapter = WikiIconMediawikiAdapter(client: client);
  ref.onDispose(adapter.dispose);
  return adapter;
});

/// Provides the WikiLinkGateway port implementation.
final wikiLinkGatewayProvider = Provider<WikiLinkGateway>((ref) {
  final client = ref.watch(httpClientProvider);
  final adapter = WikiLinkMediawikiAdapter(client: client);
  ref.onDispose(adapter.dispose);
  return adapter;
});

/// Provides the BattleboxSerializer port implementation.
final battleboxSerializerProvider = Provider<BattleboxSerializer>((ref) {
  return WikitextBattleboxSerializer();
});

/// Provides the ImageExporter port implementation.
final imageExporterProvider = Provider<ImageExporter>((ref) {
  return const PlatformImageExporter();
});

/// Provides the ExternalLinkOpener port implementation.
final externalLinkOpenerProvider = Provider<ExternalLinkOpener>((ref) {
  return const UrlLauncherExternalLinkOpener();
});

/// Provides the system clock.
final clockProvider = Provider<Clock>((ref) {
  return const SystemClock();
});

/// Provides the ID generator.
final idGeneratorProvider = Provider<IdGenerator>((ref) {
  return const TimestampIdGenerator();
});

/// Provides the battlebox seed factory.
final battleboxSeedProvider = Provider<BattleboxSeed>((ref) {
  return BattleboxSeed(ref.watch(idGeneratorProvider));
});

/// Provides the domain editor.
final battleboxDomainEditorProvider = Provider<BattleboxEditor>((ref) {
  return BattleboxEditor(
    clock: ref.watch(clockProvider),
    idGenerator: ref.watch(idGeneratorProvider),
  );
});

/// Provides editing use cases.
final battleboxEditingUseCasesProvider =
    Provider<BattleboxEditingUseCases>((ref) {
  return BattleboxEditingUseCases(
    editor: ref.watch(battleboxDomainEditorProvider),
  );
});

/// Provides the import wikitext use case.
final importWikitextProvider = Provider<ImportWikitext>((ref) {
  return ImportWikitext(ref.watch(battleboxSerializerProvider));
});

/// Provides the export wikitext use case.
final exportWikitextProvider = Provider<ExportWikitext>((ref) {
  return ExportWikitext(ref.watch(battleboxSerializerProvider));
});

/// Provides the precache planning use case.
final computePrecacheRequestsProvider = Provider<ComputePrecacheRequests>((ref) {
  return const ComputePrecacheRequests(WikitextInlineParser());
});

/// Provides the battlebox editor notifier.
final battleboxEditorNotifierProvider =
    StateNotifierProvider<BattleboxEditorNotifier, BattleBoxDoc>((ref) {
  final seed = ref.watch(battleboxSeedProvider);
  return BattleboxEditorNotifier(
    editing: ref.watch(battleboxEditingUseCasesProvider),
    importWikitext: ref.watch(importWikitextProvider),
    exportWikitext: ref.watch(exportWikitextProvider),
    initialDoc: seed.create(),
  );
});
