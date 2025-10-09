import 'package:isar/isar.dart';

part 'flashcard_entity.g.dart';

@collection
class FlashcardEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String flashcardId;

  late String studySetId;
  late String front;
  late String back;
  String? hint;
  late int difficulty;
  late DateTime createdAt;

  // SRS State fields
  double? srsEaseFactor;
  int? srsInterval;
  int? srsRepetitions;
  DateTime? srsNextReviewDate;
  DateTime? srsLastReviewDate;

  FlashcardEntity();

  FlashcardEntity.create({
    required this.flashcardId,
    required this.studySetId,
    required this.front,
    required this.back,
    this.hint,
    required this.difficulty,
    required this.createdAt,
    this.srsEaseFactor,
    this.srsInterval,
    this.srsRepetitions,
    this.srsNextReviewDate,
    this.srsLastReviewDate,
  });
}
