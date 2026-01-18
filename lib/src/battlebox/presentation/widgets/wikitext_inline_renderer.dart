import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/ports/external_link_opener.dart';
import '../../application/ports/wiki_icon_gateway.dart';
import '../../application/ports/wiki_link_gateway.dart';
import '../state/providers.dart';

// Re-export the parser for external use
export '../../domain/services/wikitext_inline_parser.dart';

import '../../domain/services/wikitext_inline_parser.dart';

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

    final wikiIconGateway = ref.read(wikiIconGatewayProvider);
    final wikiLinkGateway = ref.read(wikiLinkGatewayProvider);
    final externalLinkOpener = ref.read(externalLinkOpenerProvider);

    for (final token in tokens) {
      switch (token) {
        case InlineText():
          spans.add(TextSpan(text: token.text));

        case InlineTextMacro():
          spans.add(TextSpan(text: token.replacement));

        case InlineIconMacro():
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _IconSpan(
                gateway: wikiIconGateway,
                macro: token,
                style: style,
              ),
            ),
          );

        case InlineWikiLink():
          spans.add(
            _buildWikiLinkSpan(
              context,
              wikiLinkGateway,
              externalLinkOpener,
              token,
              style,
            ),
          );

        case InlineExternalLink():
          spans.add(
            _buildExternalLinkSpan(
              context,
              externalLinkOpener,
              token.uri,
              token.displayText,
              style,
            ),
          );

        case InlineBareUrl():
          spans.add(
            _buildExternalLinkSpan(
              context,
              externalLinkOpener,
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
    WikiLinkGateway gateway,
    ExternalLinkOpener opener,
    InlineWikiLink link,
    TextStyle style,
  ) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: _WikiLinkSpan(
        gateway: gateway,
        opener: opener,
        link: link,
        style: style,
        isInteractive: isInteractive,
        onError: _showError,
      ),
    );
  }

  InlineSpan _buildExternalLinkSpan(
    BuildContext context,
    ExternalLinkOpener opener,
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
        ..onTap = () => _onExternalLinkTap(context, opener, uri),
    );
  }

  Future<void> _onExternalLinkTap(
    BuildContext context,
    ExternalLinkOpener opener,
    Uri uri,
  ) async {
    try {
      final launched = await opener.open(uri);
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

/// Wikipedia red link color for non-existent pages.
const _redLinkColor = Color(0xFFBA0000);

/// Wikipedia blue link color for existing pages.
const _blueLinkColor = Color(0xFF0645AD);

class _WikiLinkSpan extends StatefulWidget {
  final WikiLinkGateway gateway;
  final ExternalLinkOpener opener;
  final InlineWikiLink link;
  final TextStyle style;
  final bool isInteractive;
  final void Function(BuildContext, String) onError;

  const _WikiLinkSpan({
    required this.gateway,
    required this.opener,
    required this.link,
    required this.style,
    required this.isInteractive,
    required this.onError,
  });

  @override
  State<_WikiLinkSpan> createState() => _WikiLinkSpanState();
}

class _WikiLinkSpanState extends State<_WikiLinkSpan> {
  Future<ResolvedWikiLink?>? _resolveFuture;
  bool? _exists;

  @override
  void initState() {
    super.initState();
    _startResolve();
  }

  @override
  void didUpdateWidget(_WikiLinkSpan oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.link.rawTarget != widget.link.rawTarget ||
        oldWidget.link.langPrefix != widget.link.langPrefix ||
        oldWidget.link.fragment != widget.link.fragment) {
      _startResolve();
    }
  }

  void _startResolve() {
    _resolveFuture = widget.gateway.resolve(
      rawTarget: widget.link.rawTarget,
      fragment: widget.link.fragment,
      forcedLang: widget.link.langPrefix,
    );
    _resolveFuture!.then((result) {
      if (mounted) {
        setState(() {
          _exists = result != null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Default to blue while loading, then update based on existence
    final linkColor = _exists == false ? _redLinkColor : _blueLinkColor;
    final linkStyle = widget.style.copyWith(
      color: linkColor,
      decoration: TextDecoration.underline,
      decorationColor: linkColor,
    );

    if (!widget.isInteractive) {
      return Text(widget.link.displayText, style: linkStyle);
    }

    return GestureDetector(
      onTap: () => _onTap(context),
      child: Text(widget.link.displayText, style: linkStyle),
    );
  }

  Future<void> _onTap(BuildContext context) async {
    // Try to use resolved URL if available, otherwise fallback to naive
    final resolved = await _resolveFuture;
    final String url;
    if (resolved != null) {
      url = resolved.url;
    } else {
      url = widget.gateway.buildNaiveUrl(
        rawTarget: widget.link.rawTarget,
        fragment: widget.link.fragment,
        langPrefix: widget.link.langPrefix,
      );
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (context.mounted) {
        widget.onError(context, 'Could not resolve link.');
      }
      return;
    }

    try {
      final launched = await widget.opener.open(uri);
      if (!launched && context.mounted) {
        widget.onError(context, 'Could not open link.');
      }
    } catch (_) {
      if (context.mounted) {
        widget.onError(context, 'Could not open link.');
      }
    }
  }
}

class _IconSpan extends StatelessWidget {
  final WikiIconGateway gateway;
  final InlineIconMacro macro;
  final TextStyle style;

  const _IconSpan({
    required this.gateway,
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
      future: gateway.resolveFlagIcon(
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
