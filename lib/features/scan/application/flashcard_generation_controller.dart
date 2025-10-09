import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/data_sources/study_local_data_source.dart';
import '../../../core/models/flashcard.dart';
import '../../../core/models/scanned_item.dart';
import '../../../core/services/ai_generation_service.dart';

class FlashcardGenerationState {
  const FlashcardGenerationState({
    this.proposals = const [],
    this.selectedIndices = const {},
    this.isGenerating = false,
    this.isSaving = false,
    this.error,
  });

  final List<FlashcardProposal> proposals;
  final Set<int> selectedIndices;
  final bool isGenerating;
  final bool isSaving;
  final String? error;

  FlashcardGenerationState copyWith({
    List<FlashcardProposal>? proposals,
    Set<int>? selectedIndices,
    bool? isGenerating,
    bool? isSaving,
    String? error,
  }) {
    return FlashcardGenerationState(
      proposals: proposals ?? this.proposals,
      selectedIndices: selectedIndices ?? this.selectedIndices,
      isGenerating: isGenerating ?? this.isGenerating,
      isSaving: isSaving ?? this.isSaving,
      error: error,
    );
  }
}

class FlashcardGenerationController extends StateNotifier<FlashcardGenerationState> {
  FlashcardGenerationController({
    required AIGenerationService aiService,
    required StudyLocalDataSource localDataSource,
  })  : _aiService = aiService,
        _localDataSource = localDataSource,
        super(const FlashcardGenerationState());

  final AIGenerationService _aiService;
  final StudyLocalDataSource _localDataSource;
  final _uuid = const Uuid();

  /// Generate flashcards from scanned item
  Future<void> generateFlashcards({
    required ScannedItem scannedItem,
    String? subject,
    String? level,
  }) async {
    try {
      state = state.copyWith(isGenerating: true, error: null);

      if (scannedItem.ocrText == null || scannedItem.ocrText!.isEmpty) {
        throw Exception('No text available for generation');
      }

      final proposals = await _aiService.generateFlashcards(
        text: scannedItem.ocrText!,
        imageRef: scannedItem.remoteImageUrl,
        subject: subject,
        level: level,
      );

      // Select all by default
      final selectedIndices = Set<int>.from(
        List.generate(proposals.length, (index) => index),
      );

      state = state.copyWith(
        proposals: proposals,
        selectedIndices: selectedIndices,
        isGenerating: false,
      );
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        error: e.toString(),
      );
    }
  }

  /// Toggle selection of a flashcard proposal
  void toggleSelection(int index) {
    final newSelection = Set<int>.from(state.selectedIndices);
    if (newSelection.contains(index)) {
      newSelection.remove(index);
    } else {
      newSelection.add(index);
    }
    state = state.copyWith(selectedIndices: newSelection);
  }

  /// Select all proposals
  void selectAll() {
    final allIndices = Set<int>.from(
      List.generate(state.proposals.length, (index) => index),
    );
    state = state.copyWith(selectedIndices: allIndices);
  }

  /// Deselect all proposals
  void deselectAll() {
    state = state.copyWith(selectedIndices: {});
  }

  /// Update a proposal
  void updateProposal(int index, FlashcardProposal updatedProposal) {
    final updatedProposals = List<FlashcardProposal>.from(state.proposals);
    updatedProposals[index] = updatedProposal;
    state = state.copyWith(proposals: updatedProposals);
  }

  /// Save selected flashcards to a study set
  Future<void> saveFlashcards({
    required String studySetId,
  }) async {
    try {
      state = state.copyWith(isSaving: true, error: null);

      final selectedProposals = state.selectedIndices
          .map((index) => state.proposals[index])
          .toList();

      if (selectedProposals.isEmpty) {
        throw Exception('No flashcards selected');
      }

      final flashcards = selectedProposals.map((proposal) {
        return Flashcard(
          id: _uuid.v4(),
          studySetId: studySetId,
          front: proposal.front,
          back: proposal.back,
          hint: proposal.hint,
          difficulty: proposal.difficulty,
          createdAt: DateTime.now(),
          // Initialize SRS state with defaults
          srsState: SRSState(
            easeFactor: 2.5,
            interval: 1,
            repetitions: 0,
            nextReviewDate: DateTime.now().add(const Duration(days: 1)),
          ),
        );
      }).toList();

      await _localDataSource.saveFlashcards(flashcards);

      state = state.copyWith(isSaving: false);
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        error: e.toString(),
      );
      rethrow;
    }
  }

  /// Clear state
  void clear() {
    state = const FlashcardGenerationState();
  }
}
