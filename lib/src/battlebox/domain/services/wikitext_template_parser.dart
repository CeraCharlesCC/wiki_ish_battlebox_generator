import 'package:meta/meta.dart';

import 'wikitext_balanced_scanner.dart';

@immutable
class ParsedTemplateInvocation {
  final String templateName;
  final List<String> rawParams;
  final Map<String, String> namedParams;
  final List<String> unnamedParams;

  const ParsedTemplateInvocation({
    required this.templateName,
    required this.rawParams,
    required this.namedParams,
    required this.unnamedParams,
  });

  String? get firstImageValue {
    for (var index = 1; index <= 9; index++) {
      final value = namedParams['image$index']?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    for (final value in unnamedParams) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }
}

class WikitextTemplateParser {
  final WikitextBalancedScanner _scanner;

  const WikitextTemplateParser({WikitextBalancedScanner? scanner})
    : _scanner = scanner ?? const WikitextBalancedScanner();

  ParsedTemplateInvocation? parse(String rawTemplate) {
    final trimmed = rawTemplate.trim();
    if (!trimmed.startsWith('{{') || !trimmed.endsWith('}}')) {
      return null;
    }

    try {
      final inner = trimmed.substring(2, trimmed.length - 2);
      final parts = _scanner.splitTopLevel(
        inner,
        isSeparator: (state, index) => state.isTopLevel && inner[index] == '|',
      );
      if (parts.isEmpty) {
        return null;
      }

      final templateName = parts.first.trim();
      if (templateName.isEmpty) {
        return null;
      }

      final rawParams = <String>[];
      final namedParams = <String, String>{};
      final unnamedParams = <String>[];

      for (final raw in parts.skip(1)) {
        final param = raw.trim();
        if (param.isEmpty) {
          continue;
        }
        rawParams.add(param);

        final eqIndex = _scanner.indexOfTopLevelEquals(param);
        if (eqIndex <= 0) {
          unnamedParams.add(param);
          continue;
        }

        final key = param.substring(0, eqIndex).trim().toLowerCase();
        if (key.isEmpty || !_isSupportedParamKey(key)) {
          unnamedParams.add(param);
          continue;
        }

        final value = param.substring(eqIndex + 1).trim();
        namedParams[key] = value;
      }

      return ParsedTemplateInvocation(
        templateName: templateName,
        rawParams: rawParams,
        namedParams: namedParams,
        unnamedParams: unnamedParams,
      );
    } on FormatException {
      return null;
    }
  }

  bool _isSupportedParamKey(String key) {
    return RegExp(r'^[a-z0-9 _-]+$').hasMatch(key);
  }
}
