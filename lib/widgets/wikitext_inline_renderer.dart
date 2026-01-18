import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/wiki_icon_resolver.dart';
import '../services/wiki_link_resolver.dart';
import '../services/wikitext_inline_parser.dart';

final wikiIconResolverProvider = Provider<WikiIconResolver>((ref) {
  final resolver = WikiIconResolver();
  ref.onDispose(resolver.dispose);
  return resolver;
});

final wikiLinkResolverProvider = Provider<WikiLinkResolver>((ref) {
  final resolver = WikiLinkResolver();
  ref.onDispose(resolver.dispose);
  return resolver;
});

/// Shared parser instance for inline wikitext.
const wikitextInlineParser = WikitextInlineParser();

class WikitextInlineRenderer extends ConsumerWidget {
  final String text;
  final TextStyle? textStyle;
  final TextAlign textAlign;

  /// Whether links should be interactive (clickable).
  /// Set to false during export mode to prevent gestures.
  final bool isInteractive;

  const WikitextInlineRenderer({
    super.key,
    required this.text,
    this.textStyle,
    this.textAlign = TextAlign.start,
    this.isInteractive = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = textStyle ?? DefaultTextStyle.of(context).style;
    final tokens = wikitextInlineParser.parse(text);
    final spans = <InlineSpan>[];

    for (final token in tokens) {
      switch (token) {
        case InlineText():
          spans.add(TextSpan(text: token.text));

        case InlineIconMacro():
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _IconSpan(
                resolver: ref.read(wikiIconResolverProvider),
                macro: token,
                style: style,
              ),
            ),
          );

        case InlineWikiLink():
          spans.add(
            _buildWikiLinkSpan(
              context,
              ref,
              token,
              style,
            ),
          );

        case InlineExternalLink():
          spans.add(
            _buildExternalLinkSpan(
              context,
              token.uri,
              token.displayText,
              style,
            ),
          );

        case InlineBareUrl():
          spans.add(
            _buildExternalLinkSpan(
              context,
              token.uri,
              token.uri.toString(),
              style,
            ),
          );
      }
    }

    return RichText(
      textAlign: textAlign,
      text: TextSpan(style: style, children: spans),
    );
  }

  InlineSpan _buildWikiLinkSpan(
    BuildContext context,
    WidgetRef ref,
    InlineWikiLink link,
    TextStyle style,
  ) {
    final linkStyle = style.copyWith(
      color: const Color(0xFF0645AD), // Wikipedia blue
      decoration: TextDecoration.underline,
      decorationColor: const Color(0xFF0645AD),
    );

    if (!isInteractive) {
      return TextSpan(text: link.displayText, style: linkStyle);
    }

    return TextSpan(
      text: link.displayText,
      style: linkStyle,
      recognizer: TapGestureRecognizer()
        ..onTap = () => _onWikiLinkTap(context, ref, link),
    );
  }

  InlineSpan _buildExternalLinkSpan(
    BuildContext context,
    Uri uri,
    String displayText,
    TextStyle style,
  ) {
    final linkStyle = style.copyWith(
      color: const Color(0xFF3366CC), // External link blue
      decoration: TextDecoration.underline,
      decorationColor: const Color(0xFF3366CC),
    );

    if (!isInteractive) {
      return TextSpan(text: displayText, style: linkStyle);
    }

    return TextSpan(
      text: displayText,
      style: linkStyle,
      recognizer: TapGestureRecognizer()
        ..onTap = () => _onExternalLinkTap(context, uri),
    );
  }

  Future<void> _onWikiLinkTap(
    BuildContext context,
    WidgetRef ref,
    InlineWikiLink link,
  ) async {
    final resolver = ref.read(wikiLinkResolverProvider);

    // For Milestone 1: Use naive URL generation (fast, no API call)
    // For Milestone 2: Use full resolution with probing
    final url = resolver.buildNaiveUrl(
      rawTarget: link.rawTarget,
      fragment: link.fragment,
      langPrefix: link.langPrefix,
    );

    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showError(context, 'Could not resolve link.');
      return;
    }

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        _showError(context, 'Could not open link.');
      }
    } catch (_) {
      if (context.mounted) {
        _showError(context, 'Could not open link.');
      }
    }
  }

  Future<void> _onExternalLinkTap(BuildContext context, Uri uri) async {
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        _showError(context, 'Could not open link.');
      }
    } catch (_) {
      if (context.mounted) {
        _showError(context, 'Could not open link.');
      }
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _IconSpan extends StatelessWidget {
  final WikiIconResolver resolver;
  final InlineIconMacro macro;
  final TextStyle style;

  const _IconSpan({
    required this.resolver,
    required this.macro,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = style.fontSize ?? 14;
    final height = fontSize + 2;
    final width = height * 1.4;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final widthPx = (width * dpr).round();

    return FutureBuilder<String?>(
      future: resolver.resolveFlagIcon(
        templateName: macro.templateName,
        code: macro.code,
        widthPx: widthPx,
        hostOverride: macro.hostOverride,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data != null &&
            snapshot.data!.isNotEmpty) {
          return Image.network(
            snapshot.data!,
            width: width,
            height: height,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                _fallbackText(style, macro.fallbackText),
          );
        }
        if (snapshot.hasError) {
          return _fallbackText(style, macro.fallbackText);
        }
        return SizedBox(
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      },
    );
  }

  Widget _fallbackText(TextStyle style, String text) {
    return Text(
      text,
      style: style,
    );
  }
}
