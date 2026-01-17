import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/wiki_icon_resolver.dart';

final wikiIconResolverProvider = Provider<WikiIconResolver>((ref) {
  final resolver = WikiIconResolver();
  ref.onDispose(resolver.dispose);
  return resolver;
});

class WikitextInlineRenderer extends ConsumerWidget {
  final String text;
  final TextStyle? textStyle;
  final TextAlign textAlign;

  const WikitextInlineRenderer({
    super.key,
    required this.text,
    this.textStyle,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = textStyle ?? DefaultTextStyle.of(context).style;
    final segments = _parseSegments(text);
    final spans = <InlineSpan>[];
    for (final segment in segments) {
      if (segment is _TextSegment) {
        spans.add(TextSpan(text: segment.text));
      } else if (segment is _IconSegment) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _IconSpan(
              resolver: ref.read(wikiIconResolverProvider),
              macro: segment.macro,
              style: style,
            ),
          ),
        );
      }
    }

    return RichText(
      textAlign: textAlign,
      text: TextSpan(style: style, children: spans),
    );
  }
}

class _IconSpan extends StatelessWidget {
  final WikiIconResolver resolver;
  final _IconMacro macro;
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
            errorBuilder: (_, __, ___) {
              return _fallbackText(style, macro.fallbackText);
            },
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
              color: Colors.black.withOpacity(0.08),
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

sealed class _Segment {
  const _Segment();
}

class _TextSegment extends _Segment {
  final String text;

  const _TextSegment(this.text);
}

class _IconSegment extends _Segment {
  final _IconMacro macro;

  const _IconSegment(this.macro);
}

class _IconMacro {
  final String templateName;
  final String code;
  final String? hostOverride;
  final String fallbackText;

  const _IconMacro({
    required this.templateName,
    required this.code,
    required this.hostOverride,
    required this.fallbackText,
  });
}

List<_Segment> _parseSegments(String input) {
  final regex = RegExp(r'\{\{([^{}]+)\}\}');
  final segments = <_Segment>[];
  var lastIndex = 0;
  for (final match in regex.allMatches(input)) {
    if (match.start > lastIndex) {
      segments.add(_TextSegment(input.substring(lastIndex, match.start)));
    }
    final raw = match.group(0) ?? '';
    final inner = match.group(1) ?? '';
    final macro = _parseIconMacro(inner, raw);
    if (macro == null) {
      segments.add(_TextSegment(raw));
    } else {
      segments.add(_IconSegment(macro));
    }
    lastIndex = match.end;
  }
  if (lastIndex < input.length) {
    segments.add(_TextSegment(input.substring(lastIndex)));
  }
  if (segments.isEmpty) {
    segments.add(_TextSegment(input));
  }
  return segments;
}

_IconMacro? _parseIconMacro(String content, String rawTemplate) {
  final parts = content.split('|').map((part) => part.trim()).toList();
  if (parts.isEmpty) {
    return null;
  }
  final templateName = parts.first;
  final templateKey = templateName.toLowerCase();
  if (templateKey != 'flagicon' && templateKey != 'flag icon') {
    return null;
  }
  String? code;
  String? hostOverride;
  for (var i = 1; i < parts.length; i++) {
    final part = parts[i];
    if (part.isEmpty) {
      continue;
    }
    final eqIndex = part.indexOf('=');
    if (eqIndex != -1) {
      final key = part.substring(0, eqIndex).trim().toLowerCase();
      final value = part.substring(eqIndex + 1).trim();
      if (key == 'host' || key == 'wiki') {
        hostOverride = value;
      }
    } else code ??= part;
  }
  if (code == null || code.isEmpty) {
    return null;
  }
  return _IconMacro(
    templateName: templateName,
    code: code,
    hostOverride: hostOverride,
    fallbackText: rawTemplate,
  );
}
