import 'package:equatable/equatable.dart';

enum ExerciseType { multipleChoice, trueFalse, fillInBlank }

class Exercise extends Equatable {
  const Exercise({
    required this.id,
    required this.studySetId,
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
    required this.type,
    required this.createdAt,
    this.difficulty = 3,
    this.userAnswer,
    this.isCorrect,
  });

  final String id;
  final String studySetId;
  final String question;
  final List<String> options;
  final String correctAnswer;
  final String explanation;
  final ExerciseType type;
  final int difficulty; // 1-5 scale
  final String? userAnswer;
  final bool? isCorrect;
  final DateTime createdAt;

  Exercise copyWith({
    String? id,
    String? studySetId,
    String? question,
    List<String>? options,
    String? correctAnswer,
    String? explanation,
    ExerciseType? type,
    int? difficulty,
    String? userAnswer,
    bool? isCorrect,
    DateTime? createdAt,
  }) {
    return Exercise(
      id: id ?? this.id,
      studySetId: studySetId ?? this.studySetId,
      question: question ?? this.question,
      options: options ?? this.options,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      explanation: explanation ?? this.explanation,
      type: type ?? this.type,
      difficulty: difficulty ?? this.difficulty,
      userAnswer: userAnswer ?? this.userAnswer,
      isCorrect: isCorrect ?? this.isCorrect,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        studySetId,
        question,
        options,
        correctAnswer,
        explanation,
        type,
        difficulty,
        userAnswer,
        isCorrect,
        createdAt,
      ];
}
