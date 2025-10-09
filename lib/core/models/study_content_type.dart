enum StudyContentType { studySets, flashcards, explanations, exercises }

enum StudyMaterialTag {
  biology,
  computerScience,
  engineering,
  business,
  mathematics,
  physics,
  socialScience,
  language,
}

extension StudyMaterialTagLabel on StudyMaterialTag {
  String get label {
    switch (this) {
      case StudyMaterialTag.biology:
        return 'Biology';
      case StudyMaterialTag.computerScience:
        return 'Computer Science';
      case StudyMaterialTag.engineering:
        return 'Engineering';
      case StudyMaterialTag.business:
        return 'Business';
      case StudyMaterialTag.mathematics:
        return 'Mathematics';
      case StudyMaterialTag.physics:
        return 'Physics';
      case StudyMaterialTag.socialScience:
        return 'Social Science';
      case StudyMaterialTag.language:
        return 'Language';
    }
  }
}
