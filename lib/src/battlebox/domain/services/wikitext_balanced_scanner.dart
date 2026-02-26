import 'package:meta/meta.dart';

@immutable
class ScannerState {
  final int templateDepth;
  final int wikiLinkDepth;
  final int externalLinkDepth;
  final bool inComment;
  final bool inRef;
  final bool inTagHeader;

  const ScannerState({
    required this.templateDepth,
    required this.wikiLinkDepth,
    required this.externalLinkDepth,
    required this.inComment,
    required this.inRef,
    required this.inTagHeader,
  });

  bool get isTopLevel =>
      templateDepth == 0 &&
      wikiLinkDepth == 0 &&
      externalLinkDepth == 0 &&
      !inComment &&
      !inRef &&
      !inTagHeader;
}

class WikitextBalancedScanner {
  const WikitextBalancedScanner();

  Map<String, String> parseInfoboxParams(
    String template, {
    String templateNameHint = 'Infobox military conflict',
  }) {
    final start = template.indexOf('{{');
    if (start == -1) {
      throw const FormatException('Template opening token was not found.');
    }

    final end = _findMatchingTemplateEnd(template, start);
    if (end == -1) {
      throw const FormatException('Unbalanced template: closing token was not found.');
    }

    final inner = template.substring(start + 2, end);
    final parts = splitTopLevel(
      inner,
      isSeparator: (state, index) => state.isTopLevel && inner[index] == '|',
    );

    if (parts.isEmpty) {
      return const <String, String>{};
    }

    if (templateNameHint.trim().isNotEmpty) {
      final templateName = parts.first.trim().toLowerCase();
      final hint = templateNameHint.toLowerCase();
      if (!templateName.startsWith(hint)) {
        throw FormatException('Unexpected template name: ${parts.first.trim()}');
      }
    }

    final values = <String, String>{};
    for (final rawPart in parts.skip(1)) {
      final eqIndex = indexOfTopLevelEquals(rawPart);
      if (eqIndex <= 0) {
        continue;
      }
      final key = rawPart.substring(0, eqIndex).trim();
      if (key.isEmpty) {
        continue;
      }
      final value = rawPart.substring(eqIndex + 1).trim();
      values[key] = value;
    }

    return values;
  }

  List<String> splitTopLevel(
    String input, {
    required bool Function(ScannerState state, int index) isSeparator,
  }) {
    final parts = <String>[];
    final buffer = StringBuffer();

    var templateDepth = 0;
    var wikiLinkDepth = 0;
    var externalLinkDepth = 0;
    var inComment = false;
    var inRef = false;
    var inTagHeader = false;
    var i = 0;

    ScannerState state() {
      return ScannerState(
        templateDepth: templateDepth,
        wikiLinkDepth: wikiLinkDepth,
        externalLinkDepth: externalLinkDepth,
        inComment: inComment,
        inRef: inRef,
        inTagHeader: inTagHeader,
      );
    }

    while (i < input.length) {
      if (inComment) {
        if (_startsWith(input, i, '-->')) {
          buffer.write('-->');
          inComment = false;
          i += 3;
          continue;
        }
        buffer.write(input[i]);
        i++;
        continue;
      }

      if (inRef) {
        if (_startsWithIgnoreCase(input, i, '</ref>')) {
          buffer.write(input.substring(i, i + 6));
          inRef = false;
          i += 6;
          continue;
        }
        buffer.write(input[i]);
        i++;
        continue;
      }

      if (inTagHeader) {
        final char = input[i];
        buffer.write(char);
        if (char == '>') {
          inTagHeader = false;
        }
        i++;
        continue;
      }

      if (_startsWith(input, i, '<!--')) {
        buffer.write('<!--');
        inComment = true;
        i += 4;
        continue;
      }

      if (_startsWithIgnoreCase(input, i, '<ref')) {
        final closing = input.indexOf('>', i + 1);
        if (closing == -1) {
          buffer.write(input.substring(i));
          i = input.length;
          break;
        }
        final tag = input.substring(i, closing + 1);
        buffer.write(tag);
        final isSelfClosing = tag.trimRight().endsWith('/>');
        if (!isSelfClosing) {
          inRef = true;
        }
        i = closing + 1;
        continue;
      }

      final char = input[i];
      if (char == '<') {
        inTagHeader = true;
        buffer.write(char);
        i++;
        continue;
      }

      if (_startsWith(input, i, '{{')) {
        templateDepth++;
        buffer.write('{{');
        i += 2;
        continue;
      }
      if (_startsWith(input, i, '}}')) {
        if (templateDepth == 0) {
          throw const FormatException('Template depth underflow while scanning input.');
        }
        templateDepth--;
        buffer.write('}}');
        i += 2;
        continue;
      }
      if (_startsWith(input, i, '[[')) {
        wikiLinkDepth++;
        buffer.write('[[');
        i += 2;
        continue;
      }
      if (_startsWith(input, i, ']]')) {
        if (wikiLinkDepth > 0) {
          wikiLinkDepth--;
        }
        buffer.write(']]');
        i += 2;
        continue;
      }
      if (char == '[' && !_startsWith(input, i, '[[')) {
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

      if (isSeparator(state(), i)) {
        parts.add(buffer.toString());
        buffer.clear();
        i++;
        continue;
      }

      buffer.write(char);
      i++;
    }

    if (templateDepth != 0 || inComment || inRef || inTagHeader) {
      throw const FormatException('Unbalanced markers detected while scanning input.');
    }

    parts.add(buffer.toString());
    return parts;
  }

  int indexOfTopLevelEquals(String input) {
    var templateDepth = 0;
    var wikiLinkDepth = 0;
    var externalLinkDepth = 0;
    var inComment = false;
    var inRef = false;
    var inTagHeader = false;
    var i = 0;

    while (i < input.length) {
      if (inComment) {
        if (_startsWith(input, i, '-->')) {
          inComment = false;
          i += 3;
          continue;
        }
        i++;
        continue;
      }
      if (inRef) {
        if (_startsWithIgnoreCase(input, i, '</ref>')) {
          inRef = false;
          i += 6;
          continue;
        }
        i++;
        continue;
      }
      if (inTagHeader) {
        if (input[i] == '>') {
          inTagHeader = false;
        }
        i++;
        continue;
      }

      if (_startsWith(input, i, '<!--')) {
        inComment = true;
        i += 4;
        continue;
      }
      if (_startsWithIgnoreCase(input, i, '<ref')) {
        final closing = input.indexOf('>', i + 1);
        if (closing == -1) {
          return -1;
        }
        final tag = input.substring(i, closing + 1);
        final isSelfClosing = tag.trimRight().endsWith('/>');
        if (!isSelfClosing) {
          inRef = true;
        }
        i = closing + 1;
        continue;
      }
      if (input[i] == '<') {
        inTagHeader = true;
        i++;
        continue;
      }

      if (_startsWith(input, i, '{{')) {
        templateDepth++;
        i += 2;
        continue;
      }
      if (_startsWith(input, i, '}}')) {
        if (templateDepth > 0) {
          templateDepth--;
        }
        i += 2;
        continue;
      }
      if (_startsWith(input, i, '[[')) {
        wikiLinkDepth++;
        i += 2;
        continue;
      }
      if (_startsWith(input, i, ']]')) {
        if (wikiLinkDepth > 0) {
          wikiLinkDepth--;
        }
        i += 2;
        continue;
      }
      if (input[i] == '[' && !_startsWith(input, i, '[[')) {
        if (wikiLinkDepth == 0) {
          externalLinkDepth++;
        }
        i++;
        continue;
      }
      if (input[i] == ']' && externalLinkDepth > 0 && wikiLinkDepth == 0) {
        externalLinkDepth--;
        i++;
        continue;
      }

      if (input[i] == '=' &&
          templateDepth == 0 &&
          wikiLinkDepth == 0 &&
          externalLinkDepth == 0) {
        return i;
      }
      i++;
    }

    return -1;
  }

  int _findMatchingTemplateEnd(String input, int startIndex) {
    var depth = 0;
    var i = startIndex;
    while (i < input.length - 1) {
      if (_startsWith(input, i, '{{')) {
        depth++;
        i += 2;
        continue;
      }
      if (_startsWith(input, i, '}}')) {
        depth--;
        if (depth == 0) {
          return i;
        }
        if (depth < 0) {
          throw const FormatException('Template depth underflow while finding end.');
        }
        i += 2;
        continue;
      }
      i++;
    }
    return -1;
  }

  bool _startsWith(String input, int start, String token) {
    if (start + token.length > input.length) {
      return false;
    }
    return input.substring(start, start + token.length) == token;
  }

  bool _startsWithIgnoreCase(String input, int start, String token) {
    if (start + token.length > input.length) {
      return false;
    }
    return input.substring(start, start + token.length).toLowerCase() ==
        token.toLowerCase();
  }
}
