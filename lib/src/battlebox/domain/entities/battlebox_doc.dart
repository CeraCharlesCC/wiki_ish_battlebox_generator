import 'package:meta/meta.dart';

import 'sections.dart';
import 'wikitext_import_report.dart';

/// The root document representing a Wikipedia-style battlebox/infobox.
@immutable
class BattleBoxDoc {
  static const Object _unset = Object();

  final String id;
  final String title;
  final List<SectionModel> sections;
  final String templateName;
  final DateTime? lastEdited;
  final Map<String, String> customFields;
  final WikitextImportReport? importReport;

  const BattleBoxDoc({
    required this.id,
    required this.title,
    required this.sections,
    this.templateName = 'Infobox military conflict',
    this.lastEdited,
    this.customFields = const {},
    this.importReport,
  });

  BattleBoxDoc copyWith({
    String? id,
    String? title,
    List<SectionModel>? sections,
    String? templateName,
    DateTime? lastEdited,
    Map<String, String>? customFields,
    Object? importReport = _unset,
  }) {
    return BattleBoxDoc(
      id: id ?? this.id,
      title: title ?? this.title,
      sections: sections ?? this.sections,
      templateName: templateName ?? this.templateName,
      lastEdited: lastEdited ?? this.lastEdited,
      customFields: customFields ?? this.customFields,
      importReport: identical(importReport, _unset)
          ? this.importReport
          : importReport as WikitextImportReport?,
    );
  }

  SectionModel? sectionById(String sectionId) {
    for (final section in sections) {
      if (section.id == sectionId) {
        return section;
      }
    }
    return null;
  }

  SectionModel? sectionByLabel(String label) {
    for (final section in sections) {
      if (section.label == label) {
        return section;
      }
    }
    return null;
  }
}
