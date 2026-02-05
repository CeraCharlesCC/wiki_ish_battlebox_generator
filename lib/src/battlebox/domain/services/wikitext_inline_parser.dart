/// Inline token model for wiki-ish markup.
///
/// Parses wikitext containing:
/// - Icon macros: `{{flagicon|USA}}`
/// - Explanatory footnotes: `{{Efn|...}}`
/// - Plainlist bullets: `{{Plainlist| * item }}` (items on their own lines)
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

/// Simple text substitution macro like `{{KIA}}` that maps to a replacement string.
class InlineTextMacro extends InlineToken {
  final String templateName;
  final String replacement;

  const InlineTextMacro({
    required this.templateName,
    required this.replacement,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InlineTextMacro &&
          other.templateName == templateName &&
          other.replacement == replacement;

  @override
  int get hashCode => Object.hash(templateName, replacement);

  @override
  String toString() =>
      'InlineTextMacro(templateName: "$templateName", replacement: "$replacement")';
}

/// Explanatory footnote macro like `{{Efn|Note text}}`.
class InlineEfnMacro extends InlineToken {
  final String noteRaw;
  final String fallbackText;
  final String? name;
  final String? group;

  const InlineEfnMacro({
    required this.noteRaw,
    required this.fallbackText,
    this.name,
    this.group,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InlineEfnMacro &&
          other.noteRaw == noteRaw &&
          other.fallbackText == fallbackText &&
          other.name == name &&
          other.group == group;

  @override
  int get hashCode => Object.hash(noteRaw, fallbackText, name, group);

  @override
  String toString() =>
      'InlineEfnMacro(noteRaw: "$noteRaw", fallbackText: "$fallbackText", name: $name, group: $group)';
}

/// Plainlist macro like `{{Plainlist| * item }}`.
class InlinePlainlistMacro extends InlineToken {
  final List<String> itemRaws;
  final String fallbackText;

  const InlinePlainlistMacro({
    required this.itemRaws,
    required this.fallbackText,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InlinePlainlistMacro &&
          other.fallbackText == fallbackText &&
          _listEquals(other.itemRaws, itemRaws);

  @override
  int get hashCode => Object.hash(Object.hashAll(itemRaws), fallbackText);

  @override
  String toString() =>
      'InlinePlainlistMacro(items: ${itemRaws.length}, fallbackText: "$fallbackText")';
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
        final closeIndex = _findClosingTemplate(input, i + 2);
        if (closeIndex != -1) {
          flushBuffer();
          final inner = input.substring(i + 2, closeIndex);
          final rawTemplate = input.substring(i, closeIndex + 2);
          final macro = _parseMacro(inner, rawTemplate);
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

  /// Parses a macro from the inner content (without `{{` and `}}`).
  /// Returns null if not a recognized template.
  InlineToken? _parseMacro(String content, String rawTemplate) {
    final parts = _splitTopLevelPipes(content);
    if (parts.isEmpty) {
      return null;
    }

    final templateName = parts.first.trim();
    final templateKey = templateName.toLowerCase().trim();

    // Check for text substitution macros first
    const textMacros = {
      'kia': '†',
    };
    if (textMacros.containsKey(templateKey) && parts.length == 1) {
      return InlineTextMacro(
        templateName: templateName,
        replacement: textMacros[templateKey]!,
      );
    }

    if (templateKey == 'efn') {
      final unnamed = _firstUnnamedParam(parts);
      if (unnamed == null || unnamed.isEmpty) {
        return null;
      }
      final namedParams = _namedParams(parts);
      return InlineEfnMacro(
        noteRaw: unnamed,
        fallbackText: rawTemplate,
        name: namedParams['name'],
        group: namedParams['group'],
      );
    }

    if (templateKey == 'plainlist') {
      final listRaw = _firstUnnamedParam(parts);
      if (listRaw == null || listRaw.isEmpty) {
        return null;
      }
      final normalized = listRaw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final items = <String>[];
      for (final line in normalized.split('\n')) {
        final trimmed = line.trimLeft();
        if (!trimmed.startsWith('*')) {
          continue;
        }
        var item = trimmed.substring(1);
        if (item.startsWith(' ')) {
          item = item.substring(1);
        }
        if (item.trim().isEmpty) {
          continue;
        }
        items.add(item);
      }
      if (items.isEmpty) {
        return null;
      }
      return InlinePlainlistMacro(
        itemRaws: items,
        fallbackText: rawTemplate,
      );
    }

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
    final segments = inner.split('|');
    final targetPart = segments.first.trim();
    String? labelPart;

    if (segments.length == 1) {
      // No pipe: [[Target]]
      labelPart = null;
    } else if (inner.endsWith('|')) {
      // Pipe trick: [[Target|]]
      labelPart = _applyPipeTrick(targetPart);
    } else if (_isMediaNamespaceTarget(targetPart)) {
      // For file/image links, trailing segments are often options (e.g., 18px, class=...).
      // Prefer the last non-option segment as label; otherwise fallback to target title.
      final trailing = segments
          .skip(1)
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      final nonOption = trailing.where((part) => !_looksLikeMediaOption(part)).toList();
      labelPart = nonOption.isNotEmpty ? nonOption.last : null;
    } else {
      // Has label: [[Target|Label]] or [[Target|x|Label]]
      labelPart = segments.last.trim();
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

  bool _isMediaNamespaceTarget(String target) {
    var normalized = target.trimLeft();
    if (normalized.startsWith(':')) {
      normalized = normalized.substring(1);
    }
    final colonIndex = normalized.indexOf(':');
    if (colonIndex <= 0) {
      return false;
    }
    final namespace = normalized.substring(0, colonIndex).trim().toLowerCase();
    return namespace == 'file' ||
        namespace == 'image' ||
        namespace == 'ファイル' ||
        namespace == '画像';
  }

  bool _looksLikeMediaOption(String value) {
    final lower = value.trim().toLowerCase();
    if (lower.isEmpty) {
      return false;
    }
    if (RegExp(r'^\d+\s*px$').hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'^\d*x\d+px$').hasMatch(lower)) {
      return true;
    }
    if (lower == 'thumb' ||
        lower == 'thumbnail' ||
        lower == 'frame' ||
        lower == 'frameless' ||
        lower == 'border' ||
        lower == 'right' ||
        lower == 'left' ||
        lower == 'center' ||
        lower == 'none' ||
        lower == 'upright' ||
        lower.startsWith('upright=') ||
        lower.startsWith('class=') ||
        lower.startsWith('alt=') ||
        lower.startsWith('link=') ||
        lower.startsWith('lang=')) {
      return true;
    }
    return false;
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

  /// Finds the closing `}}` matching a `{{` that starts at start-2.
  /// Returns the index of the first `}` in the closing token, or -1 if not found.
  int _findClosingTemplate(String input, int start) {
    var depth = 1;
    var i = start;
    while (i + 1 < input.length) {
      if (input[i] == '{' && input[i + 1] == '{') {
        depth++;
        i += 2;
        continue;
      }
      if (input[i] == '}' && input[i + 1] == '}') {
        depth--;
        if (depth == 0) {
          return i;
        }
        i += 2;
        continue;
      }
      i++;
    }
    return -1;
  }

  List<String> _splitTopLevelPipes(String content) {
    final parts = <String>[];
    final buffer = StringBuffer();
    var templateDepth = 0;
    var wikiLinkDepth = 0;
    var externalLinkDepth = 0;
    var i = 0;

    while (i < content.length) {
      final char = content[i];
      if (i + 1 < content.length && char == '{' && content[i + 1] == '{') {
        templateDepth++;
        buffer.write('{{');
        i += 2;
        continue;
      }
      if (i + 1 < content.length && char == '}' && content[i + 1] == '}') {
        if (templateDepth > 0) {
          templateDepth--;
        }
        buffer.write('}}');
        i += 2;
        continue;
      }
      if (i + 1 < content.length && char == '[' && content[i + 1] == '[') {
        wikiLinkDepth++;
        buffer.write('[[');
        i += 2;
        continue;
      }
      if (i + 1 < content.length && char == ']' && content[i + 1] == ']') {
        if (wikiLinkDepth > 0) {
          wikiLinkDepth--;
        }
        buffer.write(']]');
        i += 2;
        continue;
      }
      if (char == '[' && (i + 1 >= content.length || content[i + 1] != '[')) {
        if (wikiLinkDepth == 0) {
          externalLinkDepth++;
        }
        buffer.write(char);
        i++;
        continue;
      }
      if (char == ']' && externalLinkDepth > 0 && wikiLinkDepth == 0) {
        externalLinkDepth--;
        buffer.write(char);
        i++;
        continue;
      }

      if (char == '|' &&
          templateDepth == 0 &&
          wikiLinkDepth == 0 &&
          externalLinkDepth == 0) {
        parts.add(buffer.toString().trim());
        buffer.clear();
        i++;
        continue;
      }

      buffer.write(char);
      i++;
    }

    parts.add(buffer.toString().trim());
    return parts;
  }

  String? _firstUnnamedParam(List<String> parts) {
    for (var i = 1; i < parts.length; i++) {
      final part = parts[i];
      if (!_isNamedParam(part)) {
        return part.trim();
      }
    }
    return null;
  }

  Map<String, String> _namedParams(List<String> parts) {
    final params = <String, String>{};
    for (var i = 1; i < parts.length; i++) {
      final part = parts[i];
      final eqIndex = part.indexOf('=');
      if (eqIndex == -1) {
        continue;
      }
      final key = part.substring(0, eqIndex).trim().toLowerCase();
      final value = part.substring(eqIndex + 1).trim();
      if (key.isEmpty) {
        continue;
      }
      params[key] = value;
    }
    return params;
  }

  bool _isNamedParam(String part) {
    final eqIndex = part.indexOf('=');
    if (eqIndex <= 0) {
      return false;
    }
    return part.substring(0, eqIndex).trim().isNotEmpty;
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

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
