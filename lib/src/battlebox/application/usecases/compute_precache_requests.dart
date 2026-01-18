import '../../domain/entities/battlebox_doc.dart';
import '../../domain/entities/sections.dart';
import '../../../../services/wikitext_inline_parser.dart';

/// Base type for precache requests derived from a battlebox document.
sealed class PrecacheRequest {
  const PrecacheRequest();
}

/// Precache a direct image URL (e.g., media section image).
class DirectUrlRequest extends PrecacheRequest {
  final String url;

  const DirectUrlRequest(this.url);
}

/// Precache a flag icon that must be resolved via the wiki icon gateway.
class FlagIconRequest extends PrecacheRequest {
  final String templateName;
  final String code;
  final int widthPx;
  final String? hostOverride;

  const FlagIconRequest({
    required this.templateName,
    required this.code,
    required this.widthPx,
    this.hostOverride,
  });
}

/// Pure use case that extracts precache requests from a battlebox document.
class ComputePrecacheRequests {
  final WikitextInlineParser _parser;

  const ComputePrecacheRequests(this._parser);

  List<PrecacheRequest> call({
    required BattleBoxDoc doc,
    required List<double> fontSizes,
    required double devicePixelRatio,
  }) {
    final requests = <PrecacheRequest>[];

    void addText(String text) {
      if (text.trim().isEmpty) {
        return;
      }
      final tokens = _parser.parse(text);
      for (final token in tokens) {
        if (token is InlineIconMacro) {
          for (final fontSize in fontSizes) {
            final height = fontSize + 2;
            final width = height * 1.4;
            final widthPx = (width * devicePixelRatio).round();
            requests.add(
              FlagIconRequest(
                templateName: token.templateName,
                code: token.code,
                widthPx: widthPx,
                hostOverride: token.hostOverride,
              ),
            );
          }
        }
      }
    }

    addText(doc.title);

    for (final section in doc.sections) {
      if (!section.isVisible) {
        continue;
      }
      switch (section) {
        case MediaSection section:
          final url = section.imageUrl ?? '';
          if (url.trim().isNotEmpty) {
            requests.add(DirectUrlRequest(url));
          }
          if (section.caption != null) {
            addText(section.caption!);
          }
        case SingleFieldSection section:
          if (section.value != null) {
            addText(section.value!.raw);
          }
        case ListFieldSection section:
          for (final item in section.items) {
            addText(item.raw);
          }
        case MultiColumnSection section:
          for (final column in section.cells) {
            for (final cell in column) {
              addText(cell.raw);
            }
          }
      }
    }

    return requests;
  }
}
