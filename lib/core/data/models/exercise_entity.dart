import 'package:isar/isar.dart';

part 'exercise_entity.g.dart';

@collection
class ExerciseEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String exerciseId;

  late String studySetId;
  late String question;
  late List<String> options;
  late String correctAnswer;
  late String explanation;
  late int typeIndex; // Maps to ExerciseType enum
  late int difficulty;
  String? userAnswer;
  bool? isCorrect;
  late DateTime createdAt;

  ExerciseEntity();

  ExerciseEntity.create({
    required this.exerciseId,
    required this.studySetId,
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
    required this.typeIndex,
    required this.difficulty,
    this.userAnswer,
    this.isCorrect,
    required this.createdAt,
  });
}
