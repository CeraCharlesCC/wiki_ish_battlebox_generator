/// Inline token model for wiki-ish markup.
///
/// Parses wikitext containing:
/// - Icon macros: `{{flagicon|USA}}`
/// - Internal wiki links: `[[Target]]`, `[[Target|Label]]`, `[[Page#Section|Label]]`
/// - External links: `[https://example.com Label]`, `[https://example.com]`
/// - Bare URLs: `https://example.com`
library;

/// Base sealed class for all inline tokens.
sealed class InlineToken {
  const InlineToken();
}

/// Plain text segment.
class InlineText extends InlineToken {
  final String text;
  const InlineText(this.text);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is InlineText && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'InlineText("$text")';
}

/// Icon macro like `{{flagicon|USA}}` or `{{flag icon|GBR|host=ja}}`.
class InlineIconMacro extends InlineToken {
  final String templateName;
  final String code;
  final String? hostOverride;
  final String fallbackText;

  const InlineIconMacro({
    required this.templateName,
    required this.code,
    this.hostOverride,
    required this.fallbackText,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InlineIconMacro &&
          other.templateName == templateName &&
          other.code == code &&
          other.hostOverride == hostOverride &&
          other.fallbackText == fallbackText;

  @override
  int get hashCode => Object.hash(templateName, code, hostOverride, fallbackText);

  @override
  String toString() =>
      'InlineIconMacro(templateName: "$templateName", code: "$code", hostOverride: $hostOverride)';
}

/// Internal wiki link like `[[Target]]`, `[[Target|Label]]`, or `[[Page#Section|Label]]`.
class InlineWikiLink extends InlineToken {
  /// The target page (e.g., "ジュノー・ビーチの戦い" or "Page#Section").
  final String rawTarget;

  /// The display text (after pipe trick processing).
  final String displayText;

  /// Optional section fragment (e.g., "Section" from "Page#Section").
  final String? fragment;

  /// Optional explicit language prefix (e.g., "ja" from ":ja:Title").
  final String? langPrefix;

  const InlineWikiLink({
    required this.rawTarget,
    required this.displayText,
    this.fragment,
    this.langPrefix,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InlineWikiLink &&
          other.rawTarget == rawTarget &&
          other.displayText == displayText &&
          other.fragment == fragment &&
          other.langPrefix == langPrefix;

  @override
  int get hashCode => Object.hash(rawTarget, displayText, fragment, langPrefix);

  @override
  String toString() =>
      'InlineWikiLink(target: "$rawTarget", display: "$displayText", fragment: $fragment, lang: $langPrefix)';
}

/// External link like `[https://example.com Label]` or `[https://example.com]`.
class InlineExternalLink extends InlineToken {
  final Uri uri;
  final String displayText;

  const InlineExternalLink({
    required this.uri,
    required this.displayText,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InlineExternalLink &&
          other.uri == uri &&
          other.displayText == displayText;

  @override
  int get hashCode => Object.hash(uri, displayText);

  @override
  String toString() => 'InlineExternalLink(uri: $uri, display: "$displayText")';
}

/// Bare URL in text like `https://example.com`.
class InlineBareUrl extends InlineToken {
  final Uri uri;

  const InlineBareUrl(this.uri);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is InlineBareUrl && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;

  @override
  String toString() => 'InlineBareUrl($uri)';
}

/// Parser for wiki-ish inline markup.
///
/// Parses text containing `{{...}}`, `[[...]]`, `[https://... ...]`, and bare URLs.
/// Uses a single-pass scanner approach to avoid conflicts between marker types.
class WikitextInlineParser {
  const WikitextInlineParser();

  /// Parses the input text and returns a list of [InlineToken]s.
  List<InlineToken> parse(String input) {
    if (input.isEmpty) {
      return const [InlineText('')];
    }

    final tokens = <InlineToken>[];
    final buffer = StringBuffer();
    var i = 0;

    void flushBuffer() {
      if (buffer.isNotEmpty) {
        tokens.add(InlineText(buffer.toString()));
        buffer.clear();
      }
    }

    while (i < input.length) {
      // Priority 1: Icon macro `{{...}}`
      if (i + 1 < input.length && input[i] == '{' && input[i + 1] == '{') {
        final closeIndex = input.indexOf('}}', i + 2);
        if (closeIndex != -1) {
          flushBuffer();
          final inner = input.substring(i + 2, closeIndex);
          final rawTemplate = input.substring(i, closeIndex + 2);
          final macro = _parseIconMacro(inner, rawTemplate);
          if (macro != null) {
            tokens.add(macro);
          } else {
            // Not a recognized macro, treat as text
            tokens.add(InlineText(rawTemplate));
          }
          i = closeIndex + 2;
          continue;
        }
      }

      // Priority 2: Wiki link `[[...]]`
      if (i + 1 < input.length && input[i] == '[' && input[i + 1] == '[') {
        final closeIndex = _findClosingBrackets(input, i + 2, ']]');
        if (closeIndex != -1) {
          flushBuffer();
          final inner = input.substring(i + 2, closeIndex);
          final wikiLink = _parseWikiLink(inner);
          tokens.add(wikiLink);
          i = closeIndex + 2;
          continue;
        }
      }

      // Priority 3: External link `[https://...]` or `[http://...]`
      if (input[i] == '[' && (i + 1 >= input.length || input[i + 1] != '[')) {
        final afterBracket = i + 1;
        if (afterBracket < input.length) {
          final urlMatch = _startsWithUrl(input, afterBracket);
          if (urlMatch != null) {
            final closeIndex = input.indexOf(']', afterBracket + urlMatch.length);
            if (closeIndex != -1) {
              flushBuffer();
              final inner = input.substring(afterBracket, closeIndex);
              final extLink = _parseExternalLink(inner);
              if (extLink != null) {
                tokens.add(extLink);
              } else {
                // Failed to parse, treat as text
                tokens.add(InlineText(input.substring(i, closeIndex + 1)));
              }
              i = closeIndex + 1;
              continue;
            }
          }
        }
      }

      // Priority 4: Bare URL in text
      final bareUrlMatch = _startsWithUrl(input, i);
      if (bareUrlMatch != null) {
        flushBuffer();
        final urlEnd = _findUrlEnd(input, i);
        final urlStr = input.substring(i, urlEnd);
        final uri = Uri.tryParse(urlStr);
        if (uri != null) {
          tokens.add(InlineBareUrl(uri));
        } else {
          tokens.add(InlineText(urlStr));
        }
        i = urlEnd;
        continue;
      }

      // Default: regular character
      buffer.write(input[i]);
      i++;
    }

    flushBuffer();

    if (tokens.isEmpty) {
      return const [InlineText('')];
    }

    return tokens;
  }

  /// Parses an icon macro from the inner content (without `{{` and `}}`).
  /// Returns null if not a recognized icon template.
  InlineIconMacro? _parseIconMacro(String content, String rawTemplate) {
    final parts = content.split('|').map((part) => part.trim()).toList();
    if (parts.isEmpty) {
      return null;
    }

    final templateName = parts.first;
    final templateKey = templateName.toLowerCase();

    // Only recognize flagicon/flag icon templates
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

    if (code == null || code.isEmpty) {
      return null;
    }

    return InlineIconMacro(
      templateName: templateName,
      code: code,
      hostOverride: hostOverride,
      fallbackText: rawTemplate,
    );
  }

  /// Parses a wiki link from the inner content (without `[[` and `]]`).
  InlineWikiLink _parseWikiLink(String inner) {
    // Handle multiple pipes: target = first segment, label = last segment
    final pipeIndex = inner.indexOf('|');
    final lastPipeIndex = inner.lastIndexOf('|');

    String targetPart;
    String? labelPart;

    if (pipeIndex == -1) {
      // No pipe: [[Target]]
      targetPart = inner.trim();
      labelPart = null;
    } else if (lastPipeIndex == inner.length - 1) {
      // Pipe trick: [[Target|]]
      targetPart = inner.substring(0, pipeIndex).trim();
      labelPart = _applyPipeTrick(targetPart);
    } else {
      // Has label: [[Target|Label]] or [[Target|x|Label]]
      targetPart = inner.substring(0, pipeIndex).trim();
      labelPart = inner.substring(lastPipeIndex + 1).trim();
    }

    // Extract language prefix (e.g., :ja:Title or ja:Title)
    String? langPrefix;
    var normalizedTarget = targetPart;

    final langPrefixMatch = RegExp(r'^:?([a-z]{2,3}):(.+)$', caseSensitive: false)
        .firstMatch(targetPart);
    if (langPrefixMatch != null) {
      final potentialLang = langPrefixMatch.group(1)!.toLowerCase();
      // Common Wikipedia language codes (subset for validation)
      if (_isValidLangCode(potentialLang)) {
        langPrefix = potentialLang;
        normalizedTarget = langPrefixMatch.group(2)!;
      }
    }

    // Extract fragment (section)
    String? fragment;
    final hashIndex = normalizedTarget.indexOf('#');
    if (hashIndex != -1) {
      fragment = normalizedTarget.substring(hashIndex + 1).trim();
      normalizedTarget = normalizedTarget.substring(0, hashIndex).trim();
    }

    // Determine display text
    final displayText = labelPart ?? _defaultDisplayText(normalizedTarget, fragment);

    return InlineWikiLink(
      rawTarget: normalizedTarget,
      displayText: displayText,
      fragment: fragment?.isNotEmpty == true ? fragment : null,
      langPrefix: langPrefix,
    );
  }

  /// Applies the pipe trick to generate display text.
  /// Rules:
  /// 1. Remove any prefix before the first `:` (namespace/interwiki)
  /// 2. Remove trailing parenthetical `(...)` if present
  /// 3. Else remove trailing `, ...` if present
  String _applyPipeTrick(String target) {
    var result = target;

    // Rule 1: Remove prefix before first `:`
    final colonIndex = result.indexOf(':');
    if (colonIndex != -1) {
      result = result.substring(colonIndex + 1);
    }

    // Remove fragment if present
    final hashIndex = result.indexOf('#');
    if (hashIndex != -1) {
      result = result.substring(0, hashIndex);
    }

    result = result.trim();

    // Rule 2: Remove trailing parenthetical
    final parenMatch = RegExp(r'^(.+?)\s*\([^)]*\)$').firstMatch(result);
    if (parenMatch != null) {
      return parenMatch.group(1)!.trim();
    }

    // Rule 3: Remove trailing comma disambiguation
    final commaMatch = RegExp(r'^(.+?),\s*.+$').firstMatch(result);
    if (commaMatch != null) {
      return commaMatch.group(1)!.trim();
    }

    return result;
  }

  /// Default display text when no label is provided.
  String _defaultDisplayText(String target, String? fragment) {
    if (target.isEmpty && fragment != null) {
      // [[#Section]] style link
      return fragment;
    }
    return target;
  }

  /// Parses an external link from the inner content (without `[` and `]`).
  InlineExternalLink? _parseExternalLink(String inner) {
    // External links separate URL and label by space
    final spaceIndex = inner.indexOf(' ');

    String urlPart;
    String? labelPart;

    if (spaceIndex == -1) {
      // No label: [https://example.com]
      urlPart = inner.trim();
      labelPart = null;
    } else {
      urlPart = inner.substring(0, spaceIndex).trim();
      labelPart = inner.substring(spaceIndex + 1).trim();
    }

    final uri = Uri.tryParse(urlPart);
    if (uri == null || !uri.hasScheme) {
      return null;
    }

    return InlineExternalLink(
      uri: uri,
      displayText: labelPart?.isNotEmpty == true ? labelPart! : urlPart,
    );
  }

  /// Checks if the input at the given position starts with a URL.
  /// Returns the URL prefix match length if found, null otherwise.
  String? _startsWithUrl(String input, int start) {
    if (start + 7 <= input.length && input.substring(start, start + 7) == 'http://') {
      return 'http://';
    }
    if (start + 8 <= input.length && input.substring(start, start + 8) == 'https://') {
      return 'https://';
    }
    return null;
  }

  /// Finds the end of a bare URL starting at the given position.
  int _findUrlEnd(String input, int start) {
    var end = start;
    // URL characters: alphanumeric, and common URL punctuation
    // Stop at whitespace, certain punctuation that typically ends URLs
    final urlChars = RegExp(r'''[a-zA-Z0-9\-._~:/?#\[\]@!$&'()*+,;=%]''');

    while (end < input.length) {
      final char = input[end];
      if (!urlChars.hasMatch(char)) {
        break;
      }
      end++;
    }

    // Trim trailing punctuation that's likely not part of the URL
    while (end > start) {
      final lastChar = input[end - 1];
      if ('.,:;!?\'")}]'.contains(lastChar)) {
        // Check if it's a balanced paren/bracket
        if (lastChar == ')' && _countChar(input.substring(start, end), '(') >
            _countChar(input.substring(start, end), ')') - 1) {
          break;
        }
        if (lastChar == ']' && _countChar(input.substring(start, end), '[') >
            _countChar(input.substring(start, end), ']') - 1) {
          break;
        }
        end--;
      } else {
        break;
      }
    }

    return end;
  }

  int _countChar(String s, String c) {
    var count = 0;
    for (var i = 0; i < s.length; i++) {
      if (s[i] == c) count++;
    }
    return count;
  }

  /// Finds the closing brackets (e.g., `]]`) starting search from the given position.
  /// Returns -1 if not found.
  int _findClosingBrackets(String input, int start, String closing) {
    return input.indexOf(closing, start);
  }

  /// Checks if a string is a valid Wikipedia language code.
  bool _isValidLangCode(String code) {
    // Common Wikipedia language codes (this is a subset, full validation
    // would require checking against SiteMatrix)
    const commonLangCodes = {
      'en', 'ja', 'de', 'fr', 'es', 'it', 'pt', 'ru', 'zh', 'ko', 'ar', 'nl',
      'pl', 'sv', 'uk', 'vi', 'fa', 'he', 'id', 'tr', 'cs', 'fi', 'no', 'hu',
      'ro', 'da', 'th', 'el', 'bg', 'sr', 'sk', 'hr', 'lt', 'sl', 'et', 'lv',
      'simple', 'ca', 'hi', 'bn', 'ta', 'te', 'mr', 'ur', 'ms', 'tl',
    };
    return commonLangCodes.contains(code);
  }
}
