import 'package:meta/meta.dart';

import 'sections.dart';

/// The root document representing a Wikipedia-style battlebox/infobox.
@immutable
class BattleBoxDoc {
  final String id;
  final String title;
  final List<SectionModel> sections;
  final String templateName;
  final DateTime? lastEdited;
  final Map<String, String> customFields;

  const BattleBoxDoc({
    required this.id,
    required this.title,
    required this.sections,
    this.templateName = 'Infobox military conflict',
    this.lastEdited,
    this.customFields = const {},
  });

  BattleBoxDoc copyWith({
    String? id,
    String? title,
    List<SectionModel>? sections,
    String? templateName,
    DateTime? lastEdited,
    Map<String, String>? customFields,
  }) {
    return BattleBoxDoc(
      id: id ?? this.id,
      title: title ?? this.title,
      sections: sections ?? this.sections,
      templateName: templateName ?? this.templateName,
      lastEdited: lastEdited ?? this.lastEdited,
      customFields: customFields ?? this.customFields,
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
