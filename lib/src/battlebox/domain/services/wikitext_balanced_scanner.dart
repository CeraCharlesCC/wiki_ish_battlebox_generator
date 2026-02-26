import 'package:meta/meta.dart';

bool wikitextStartsWithToken(String input, int start, String token) {
  if (start + token.length > input.length) {
    return false;
  }
  return input.substring(start, start + token.length) == token;
}

bool wikitextStartsWithTokenIgnoreCase(String input, int start, String token) {
  if (start + token.length > input.length) {
    return false;
  }
  return input.substring(start, start + token.length).toLowerCase() ==
      token.toLowerCase();
}

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

enum _TopLevelCharAction { include, consume, stop }

enum _MalformedRefTagBehavior { appendRemainderAndStop, returnNotFound }

class _MutableScannerState {
  int templateDepth = 0;
  int wikiLinkDepth = 0;
  int externalLinkDepth = 0;
  bool inComment = false;
  bool inRef = false;
  bool inTagHeader = false;

  bool get hasUnbalancedMarkers =>
      templateDepth != 0 || inComment || inRef || inTagHeader;

  ScannerState snapshot() {
    return ScannerState(
      templateDepth: templateDepth,
      wikiLinkDepth: wikiLinkDepth,
      externalLinkDepth: externalLinkDepth,
      inComment: inComment,
      inRef: inRef,
      inTagHeader: inTagHeader,
    );
  }
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

    final end = findClosingTemplate(template, start + 2);
    if (end == -1) {
      throw const FormatException(
        'Unbalanced template: closing token was not found.',
      );
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
        throw FormatException(
          'Unexpected template name: ${parts.first.trim()}',
        );
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
    _scanInput(
      input,
      buffer: buffer,
      throwOnTemplateUnderflow: true,
      throwOnUnbalancedMarkers: true,
      malformedRefTagBehavior: _MalformedRefTagBehavior.appendRemainderAndStop,
      onTopLevelChar: (state, index) {
        if (isSeparator(state, index)) {
          parts.add(buffer.toString());
          buffer.clear();
          return _TopLevelCharAction.consume;
        }
        return _TopLevelCharAction.include;
      },
    );

    parts.add(buffer.toString());
    return parts;
  }

  int indexOfTopLevelEquals(String input) {
    return _scanInput(
      input,
      malformedRefTagBehavior: _MalformedRefTagBehavior.returnNotFound,
      onTopLevelChar: (state, index) {
        if (state.isTopLevel && input[index] == '=') {
          return _TopLevelCharAction.stop;
        }
        return _TopLevelCharAction.include;
      },
    );
  }

  int findClosingTemplate(String input, int start, {int initialDepth = 1}) {
    var depth = initialDepth;
    var i = start;
    while (i < input.length - 1) {
      if (wikitextStartsWithToken(input, i, '{{')) {
        depth++;
        i += 2;
        continue;
      }
      if (wikitextStartsWithToken(input, i, '}}')) {
        depth--;
        if (depth == 0) {
          return i;
        }
        if (depth < 0) {
          throw const FormatException(
            'Template depth underflow while finding end.',
          );
        }
        i += 2;
        continue;
      }
      i++;
    }
    return -1;
  }

  int _scanInput(
    String input, {
    StringBuffer? buffer,
    required _TopLevelCharAction Function(ScannerState state, int index)
    onTopLevelChar,
    required _MalformedRefTagBehavior malformedRefTagBehavior,
    bool throwOnTemplateUnderflow = false,
    bool throwOnUnbalancedMarkers = false,
  }) {
    final state = _MutableScannerState();
    var i = 0;

    void writeText(String text) {
      buffer?.write(text);
    }

    while (i < input.length) {
      if (state.inComment) {
        if (wikitextStartsWithToken(input, i, '-->')) {
          writeText('-->');
          state.inComment = false;
          i += 3;
          continue;
        }
        writeText(input[i]);
        i++;
        continue;
      }

      if (state.inRef) {
        if (wikitextStartsWithTokenIgnoreCase(input, i, '</ref>')) {
          writeText(input.substring(i, i + 6));
          state.inRef = false;
          i += 6;
          continue;
        }
        writeText(input[i]);
        i++;
        continue;
      }

      if (state.inTagHeader) {
        final char = input[i];
        writeText(char);
        if (char == '>') {
          state.inTagHeader = false;
        }
        i++;
        continue;
      }

      if (wikitextStartsWithToken(input, i, '<!--')) {
        writeText('<!--');
        state.inComment = true;
        i += 4;
        continue;
      }

      if (wikitextStartsWithTokenIgnoreCase(input, i, '<ref')) {
        final closing = input.indexOf('>', i + 1);
        if (closing == -1) {
          if (malformedRefTagBehavior ==
              _MalformedRefTagBehavior.appendRemainderAndStop) {
            writeText(input.substring(i));
            break;
          }
          return -1;
        }
        final tag = input.substring(i, closing + 1);
        writeText(tag);
        final isSelfClosing = tag.trimRight().endsWith('/>');
        if (!isSelfClosing) {
          state.inRef = true;
        }
        i = closing + 1;
        continue;
      }

      final char = input[i];
      if (char == '<') {
        state.inTagHeader = true;
        writeText(char);
        i++;
        continue;
      }

      if (wikitextStartsWithToken(input, i, '{{')) {
        state.templateDepth++;
        writeText('{{');
        i += 2;
        continue;
      }
      if (wikitextStartsWithToken(input, i, '}}')) {
        if (state.templateDepth == 0 && throwOnTemplateUnderflow) {
          throw const FormatException(
            'Template depth underflow while scanning input.',
          );
        }
        if (state.templateDepth > 0) {
          state.templateDepth--;
        }
        writeText('}}');
        i += 2;
        continue;
      }
      if (wikitextStartsWithToken(input, i, '[[')) {
        state.wikiLinkDepth++;
        writeText('[[');
        i += 2;
        continue;
      }
      if (wikitextStartsWithToken(input, i, ']]')) {
        if (state.wikiLinkDepth > 0) {
          state.wikiLinkDepth--;
        }
        writeText(']]');
        i += 2;
        continue;
      }
      if (char == '[' && !wikitextStartsWithToken(input, i, '[[')) {
        if (state.wikiLinkDepth == 0) {
          state.externalLinkDepth++;
        }
        writeText(char);
        i++;
        continue;
      }
      if (char == ']' &&
          state.externalLinkDepth > 0 &&
          state.wikiLinkDepth == 0) {
        state.externalLinkDepth--;
        writeText(char);
        i++;
        continue;
      }

      final action = onTopLevelChar(state.snapshot(), i);
      if (action == _TopLevelCharAction.stop) {
        return i;
      }
      if (action == _TopLevelCharAction.consume) {
        i++;
        continue;
      }

      writeText(char);
      i++;
    }

    if (throwOnUnbalancedMarkers && state.hasUnbalancedMarkers) {
      throw const FormatException(
        'Unbalanced markers detected while scanning input.',
      );
    }
    return -1;
  }
}
