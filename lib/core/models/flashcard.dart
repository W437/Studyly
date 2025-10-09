import 'package:equatable/equatable.dart';

class Flashcard extends Equatable {
  const Flashcard({
    required this.id,
    required this.studySetId,
    required this.front,
    required this.back,
    required this.createdAt,
    this.hint,
    this.difficulty = 3,
    this.srsState,
  });

  final String id;
  final String studySetId;
  final String front;
  final String back;
  final String? hint;
  final int difficulty; // 1-5 scale
  final SRSState? srsState;
  final DateTime createdAt;

  Flashcard copyWith({
    String? id,
    String? studySetId,
    String? front,
    String? back,
    String? hint,
    int? difficulty,
    SRSState? srsState,
    DateTime? createdAt,
  }) {
    return Flashcard(
      id: id ?? this.id,
      studySetId: studySetId ?? this.studySetId,
      front: front ?? this.front,
      back: back ?? this.back,
      hint: hint ?? this.hint,
      difficulty: difficulty ?? this.difficulty,
      srsState: srsState ?? this.srsState,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        studySetId,
        front,
        back,
        hint,
        difficulty,
        srsState,
        createdAt,
      ];
}

/// Spaced Repetition System state
class SRSState extends Equatable {
  const SRSState({
    required this.easeFactor,
    required this.interval,
    required this.repetitions,
    required this.nextReviewDate,
    this.lastReviewDate,
  });

  final double easeFactor; // 1.3 - 2.5
  final int interval; // days until next review
  final int repetitions; // number of successful reviews
  final DateTime nextReviewDate;
  final DateTime? lastReviewDate;

  SRSState copyWith({
    double? easeFactor,
    int? interval,
    int? repetitions,
    DateTime? nextReviewDate,
    DateTime? lastReviewDate,
  }) {
    return SRSState(
      easeFactor: easeFactor ?? this.easeFactor,
      interval: interval ?? this.interval,
      repetitions: repetitions ?? this.repetitions,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
      lastReviewDate: lastReviewDate ?? this.lastReviewDate,
    );
  }

  @override
  List<Object?> get props => [
        easeFactor,
        interval,
        repetitions,
        nextReviewDate,
        lastReviewDate,
      ];
}
