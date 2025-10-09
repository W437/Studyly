import 'package:isar/isar.dart';

part 'study_set_entity.g.dart';

@collection
class StudySetEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String studySetId;

  late String title;
  late int flashcards;
  late int explanations;
  late int exercises;
  late String views;
  late int borderColor;
  late int tagIndex;
  late String description;

  StudySetEntity();

  StudySetEntity.create({
    required this.studySetId,
    required this.title,
    required this.flashcards,
    required this.explanations,
    required this.exercises,
    required this.views,
    required this.borderColor,
    required this.tagIndex,
    required this.description,
  });
}
