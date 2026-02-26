import 'package:meta/meta.dart';

enum ImportFieldStatus { parsed, partial, failed, skipped }

@immutable
class ImportFieldReport {
  final String key;
  final ImportFieldStatus status;
  final int parsedItemCount;
  final List<String> unparsedFragments;
  final String? firstOffendingToken;

  const ImportFieldReport({
    required this.key,
    required this.status,
    required this.parsedItemCount,
    this.unparsedFragments = const [],
    this.firstOffendingToken,
  });
}

@immutable
class WikitextImportReport {
  final Map<String, ImportFieldReport> fields;

  const WikitextImportReport({required this.fields});

  Iterable<String> get parsedKeys => _keysForStatus(ImportFieldStatus.parsed);

  Iterable<String> get partialKeys => _keysForStatus(ImportFieldStatus.partial);

  Iterable<String> get failedKeys => _keysForStatus(ImportFieldStatus.failed);

  int get parsedCount => parsedKeys.length;

  int get partialCount => partialKeys.length;

  int get failedCount => failedKeys.length;

  Iterable<String> _keysForStatus(ImportFieldStatus status) {
    return fields.entries
        .where((entry) => entry.value.status == status)
        .map((entry) => entry.key);
  }
}
