import '../models/flashcard.dart';

/// Implements the SM-2 (SuperMemo 2) spaced repetition algorithm
/// This algorithm schedules review intervals based on user performance
class SRSAlgorithmService {
  /// Calculate next SRS state based on user's answer difficulty
  ///
  /// Difficulty scale:
  /// - 1: Again (forgot, restart)
  /// - 2: Hard (difficult to recall)
  /// - 3: Good (recalled with some effort)
  /// - 4: Easy (recalled instantly)
  SRSState calculateNextState({
    required SRSState? currentState,
    required int difficulty,
  }) {
    // Initialize state if this is the first review
    if (currentState == null) {
      return _initializeState(difficulty);
    }

    final quality = _mapDifficultyToQuality(difficulty);

    // Update ease factor
    final newEaseFactor = _calculateEaseFactor(
      currentEaseFactor: currentState.easeFactor,
      quality: quality,
    );

    // Calculate new interval based on difficulty
    final newInterval = _calculateInterval(
      currentInterval: currentState.interval,
      repetitions: currentState.repetitions,
      quality: quality,
      easeFactor: newEaseFactor,
    );

    // Update repetition count
    final newRepetitions = difficulty >= 3
        ? currentState.repetitions + 1
        : 0; // Reset if failed

    final now = DateTime.now();
    final nextReviewDate = now.add(Duration(days: newInterval));

    return SRSState(
      easeFactor: newEaseFactor,
      interval: newInterval,
      repetitions: newRepetitions,
      nextReviewDate: nextReviewDate,
      lastReviewDate: now,
    );
  }

  /// Initialize SRS state for first review
  SRSState _initializeState(int difficulty) {
    final now = DateTime.now();

    // First interval based on initial difficulty
    final interval = switch (difficulty) {
      1 => 0, // Review again today
      2 => 1, // Review tomorrow
      3 => 1, // Review tomorrow
      4 => 4, // Review in 4 days
      _ => 1,
    };

    return SRSState(
      easeFactor: 2.5, // Default starting ease factor
      interval: interval,
      repetitions: difficulty >= 3 ? 1 : 0,
      nextReviewDate: now.add(Duration(days: interval)),
      lastReviewDate: now,
    );
  }

  /// Map difficulty (1-4) to SM-2 quality (0-5)
  int _mapDifficultyToQuality(int difficulty) {
    return switch (difficulty) {
      1 => 0, // Complete blackout
      2 => 3, // Correct response recalled with serious difficulty
      3 => 4, // Correct response after a hesitation
      4 => 5, // Perfect response
      _ => 3,
    };
  }

  /// Calculate new ease factor based on SM-2 algorithm
  /// EF' = EF + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
  double _calculateEaseFactor({
    required double currentEaseFactor,
    required int quality,
  }) {
    final newEaseFactor = currentEaseFactor +
        (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));

    // Clamp ease factor between 1.3 and 2.5
    return newEaseFactor.clamp(1.3, 2.5);
  }

  /// Calculate interval in days
  int _calculateInterval({
    required int currentInterval,
    required int repetitions,
    required int quality,
    required double easeFactor,
  }) {
    // If failed (quality < 3), restart
    if (quality < 3) {
      return 0; // Review again today
    }

    // First successful review
    if (repetitions == 0) {
      return 1;
    }

    // Second successful review
    if (repetitions == 1) {
      return 6;
    }

    // Subsequent reviews: multiply by ease factor
    return (currentInterval * easeFactor).round();
  }

  /// Get all flashcards that are due for review
  List<Flashcard> getDueFlashcards(List<Flashcard> allFlashcards) {
    final now = DateTime.now();

    return allFlashcards.where((card) {
      // Cards without SRS state are considered new and due
      if (card.srsState == null) {
        return true;
      }

      // Check if next review date has passed
      return card.srsState!.nextReviewDate.isBefore(now) ||
          card.srsState!.nextReviewDate.isAtSameMomentAs(now);
    }).toList();
  }

  /// Get count of due flashcards
  int getDueCount(List<Flashcard> allFlashcards) {
    return getDueFlashcards(allFlashcards).length;
  }

  /// Check if a flashcard is due for review
  bool isDue(Flashcard flashcard) {
    if (flashcard.srsState == null) {
      return true; // New cards are always due
    }

    final now = DateTime.now();
    return flashcard.srsState!.nextReviewDate.isBefore(now) ||
        flashcard.srsState!.nextReviewDate.isAtSameMomentAs(now);
  }

  /// Get flashcards grouped by their review status
  Map<ReviewStatus, List<Flashcard>> groupByStatus(
    List<Flashcard> allFlashcards,
  ) {
    final now = DateTime.now();
    final groups = <ReviewStatus, List<Flashcard>>{
      ReviewStatus.newCard: [],
      ReviewStatus.learning: [],
      ReviewStatus.review: [],
      ReviewStatus.mastered: [],
    };

    for (final card in allFlashcards) {
      final status = _getReviewStatus(card, now);
      groups[status]!.add(card);
    }

    return groups;
  }

  /// Determine review status of a card
  ReviewStatus _getReviewStatus(Flashcard card, DateTime now) {
    if (card.srsState == null) {
      return ReviewStatus.newCard;
    }

    final state = card.srsState!;

    // Mastered: high ease factor and long interval
    if (state.easeFactor >= 2.3 && state.interval >= 21) {
      return ReviewStatus.mastered;
    }

    // Learning: low repetitions
    if (state.repetitions < 3) {
      return ReviewStatus.learning;
    }

    // Review: everything else
    return ReviewStatus.review;
  }
}

/// Status of a flashcard in the review process
enum ReviewStatus {
  newCard,
  learning,
  review,
  mastered,
}
