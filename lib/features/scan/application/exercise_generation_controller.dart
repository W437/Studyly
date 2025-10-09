import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/data_sources/study_local_data_source.dart';
import '../../../core/models/exercise.dart';
import '../../../core/models/scanned_item.dart';
import '../../../core/services/ai_generation_service.dart';

class ExerciseGenerationState {
  const ExerciseGenerationState({
    this.proposals = const [],
    this.selectedIndices = const {},
    this.isGenerating = false,
    this.isSaving = false,
    this.error,
  });

  final List<ExerciseProposal> proposals;
  final Set<int> selectedIndices;
  final bool isGenerating;
  final bool isSaving;
  final String? error;

  ExerciseGenerationState copyWith({
    List<ExerciseProposal>? proposals,
    Set<int>? selectedIndices,
    bool? isGenerating,
    bool? isSaving,
    String? error,
  }) {
    return ExerciseGenerationState(
      proposals: proposals ?? this.proposals,
      selectedIndices: selectedIndices ?? this.selectedIndices,
      isGenerating: isGenerating ?? this.isGenerating,
      isSaving: isSaving ?? this.isSaving,
      error: error,
    );
  }
}

class ExerciseGenerationController extends StateNotifier<ExerciseGenerationState> {
  ExerciseGenerationController({
    required AIGenerationService aiService,
    required StudyLocalDataSource localDataSource,
  })  : _aiService = aiService,
        _localDataSource = localDataSource,
        super(const ExerciseGenerationState());

  final AIGenerationService _aiService;
  final StudyLocalDataSource _localDataSource;
  final _uuid = const Uuid();

  /// Generate exercises from scanned item
  Future<void> generateExercises({
    required ScannedItem scannedItem,
    String? subject,
    String? level,
    int count = 5,
  }) async {
    try {
      state = state.copyWith(isGenerating: true, error: null);

      if (scannedItem.ocrText == null || scannedItem.ocrText!.isEmpty) {
        throw Exception('No text available for generation');
      }

      final proposals = await _aiService.generateExercises(
        text: scannedItem.ocrText!,
        imageRef: scannedItem.remoteImageUrl,
        subject: subject,
        level: level,
        count: count,
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

  /// Toggle selection of an exercise proposal
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
  void updateProposal(int index, ExerciseProposal updatedProposal) {
    final updatedProposals = List<ExerciseProposal>.from(state.proposals);
    updatedProposals[index] = updatedProposal;
    state = state.copyWith(proposals: updatedProposals);
  }

  /// Save selected exercises to a study set
  Future<void> saveExercises({
    required String studySetId,
  }) async {
    try {
      state = state.copyWith(isSaving: true, error: null);

      final selectedProposals = state.selectedIndices
          .map((index) => state.proposals[index])
          .toList();

      if (selectedProposals.isEmpty) {
        throw Exception('No exercises selected');
      }

      final exercises = selectedProposals.map((proposal) {
        return Exercise(
          id: _uuid.v4(),
          studySetId: studySetId,
          question: proposal.question,
          options: proposal.options,
          correctAnswer: proposal.correctAnswer,
          explanation: proposal.explanation,
          type: ExerciseType.multipleChoice,
          difficulty: proposal.difficulty,
          createdAt: DateTime.now(),
        );
      }).toList();

      await _localDataSource.saveExercises(exercises);

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
    state = const ExerciseGenerationState();
  }
}
