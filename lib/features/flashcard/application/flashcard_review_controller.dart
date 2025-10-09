import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/flashcard.dart';
import '../../../core/services/srs_algorithm_service.dart';
import '../../../core/services/study_repository.dart';

class FlashcardReviewState {
  const FlashcardReviewState({
    this.flashcards = const [],
    this.currentIndex = 0,
    this.isFlipped = false,
    this.isLoading = false,
    this.isCompleted = false,
    this.error,
  });

  final List<Flashcard> flashcards;
  final int currentIndex;
  final bool isFlipped;
  final bool isLoading;
  final bool isCompleted;
  final String? error;

  Flashcard? get currentCard =>
      flashcards.isEmpty ? null : flashcards[currentIndex];

  int get totalCards => flashcards.length;

  FlashcardReviewState copyWith({
    List<Flashcard>? flashcards,
    int? currentIndex,
    bool? isFlipped,
    bool? isLoading,
    bool? isCompleted,
    String? error,
  }) {
    return FlashcardReviewState(
      flashcards: flashcards ?? this.flashcards,
      currentIndex: currentIndex ?? this.currentIndex,
      isFlipped: isFlipped ?? this.isFlipped,
      isLoading: isLoading ?? this.isLoading,
      isCompleted: isCompleted ?? this.isCompleted,
      error: error,
    );
  }
}

class FlashcardReviewController extends StateNotifier<FlashcardReviewState> {
  FlashcardReviewController({
    required StudyRepository studyRepository,
    required SRSAlgorithmService srsService,
  })  : _studyRepository = studyRepository,
        _srsService = srsService,
        super(const FlashcardReviewState());

  final StudyRepository _studyRepository;
  final SRSAlgorithmService _srsService;

  /// Start a review session for a study set
  /// Only loads flashcards that are due for review
  Future<void> startReviewSession(String studySetId) async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      // Get all flashcards for the study set
      final allFlashcards =
          await _studyRepository.getFlashcardsByStudySet(studySetId);

      if (allFlashcards.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: 'No flashcards found in this study set',
        );
        return;
      }

      // Filter for due flashcards
      final dueFlashcards = _srsService.getDueFlashcards(allFlashcards);

      if (dueFlashcards.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          isCompleted: true,
          flashcards: allFlashcards, // Keep all cards for stats
        );
        return;
      }

      // Shuffle for variety
      final shuffled = List<Flashcard>.from(dueFlashcards)..shuffle();

      state = state.copyWith(
        flashcards: shuffled,
        currentIndex: 0,
        isFlipped: false,
        isLoading: false,
        isCompleted: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Flip the current card
  void flipCard() {
    state = state.copyWith(isFlipped: !state.isFlipped);
  }

  /// Answer the current card and move to next
  Future<void> answerCard(int difficulty) async {
    if (state.currentCard == null) return;

    try {
      final currentCard = state.currentCard!;

      // Calculate new SRS state
      final newSRSState = _srsService.calculateNextState(
        currentState: currentCard.srsState,
        difficulty: difficulty,
      );

      // Update flashcard with new SRS state
      final updatedCard = currentCard.copyWith(srsState: newSRSState);

      // Save to repository
      await _studyRepository.updateFlashcard(updatedCard);

      // Move to next card
      final nextIndex = state.currentIndex + 1;

      if (nextIndex >= state.flashcards.length) {
        // Review session completed
        state = state.copyWith(
          isCompleted: true,
          isFlipped: false,
        );
      } else {
        // Move to next card
        state = state.copyWith(
          currentIndex: nextIndex,
          isFlipped: false,
        );
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Skip to next card without answering
  void skipCard() {
    final nextIndex = state.currentIndex + 1;

    if (nextIndex >= state.flashcards.length) {
      state = state.copyWith(
        isCompleted: true,
        isFlipped: false,
      );
    } else {
      state = state.copyWith(
        currentIndex: nextIndex,
        isFlipped: false,
      );
    }
  }

  /// Reset the review session
  void reset() {
    state = const FlashcardReviewState();
  }
}

/// Provider for flashcard review controller
final flashcardReviewControllerProvider =
    StateNotifierProvider<FlashcardReviewController, FlashcardReviewState>(
  (ref) {
    // These providers will be defined in study_providers.dart
    throw UnimplementedError(
      'flashcardReviewControllerProvider must be overridden with actual dependencies',
    );
  },
);
