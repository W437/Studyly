import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/data_sources/study_local_data_source.dart';
import '../../../core/models/explanation_doc.dart';
import '../../../core/models/scanned_item.dart';
import '../../../core/services/ai_generation_service.dart';

class ExplanationGenerationState {
  const ExplanationGenerationState({
    this.proposal,
    this.editedProposal,
    this.isGenerating = false,
    this.isSaving = false,
    this.error,
  });

  final ExplanationProposal? proposal;
  final ExplanationProposal? editedProposal;
  final bool isGenerating;
  final bool isSaving;
  final String? error;

  ExplanationGenerationState copyWith({
    ExplanationProposal? proposal,
    ExplanationProposal? editedProposal,
    bool? isGenerating,
    bool? isSaving,
    String? error,
  }) {
    return ExplanationGenerationState(
      proposal: proposal ?? this.proposal,
      editedProposal: editedProposal ?? this.editedProposal,
      isGenerating: isGenerating ?? this.isGenerating,
      isSaving: isSaving ?? this.isSaving,
      error: error,
    );
  }

  ExplanationProposal get currentProposal => editedProposal ?? proposal!;
}

class ExplanationGenerationController extends StateNotifier<ExplanationGenerationState> {
  ExplanationGenerationController({
    required AIGenerationService aiService,
    required StudyLocalDataSource localDataSource,
  })  : _aiService = aiService,
        _localDataSource = localDataSource,
        super(const ExplanationGenerationState());

  final AIGenerationService _aiService;
  final StudyLocalDataSource _localDataSource;
  final _uuid = const Uuid();

  /// Generate explanation from scanned item
  Future<void> generateExplanation({
    required ScannedItem scannedItem,
    String? subject,
    String? level,
  }) async {
    try {
      state = state.copyWith(isGenerating: true, error: null);

      if (scannedItem.ocrText == null || scannedItem.ocrText!.isEmpty) {
        throw Exception('No text available for generation');
      }

      final proposal = await _aiService.generateExplanation(
        text: scannedItem.ocrText!,
        imageRef: scannedItem.remoteImageUrl,
        subject: subject,
        level: level,
      );

      state = state.copyWith(
        proposal: proposal,
        isGenerating: false,
      );
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        error: e.toString(),
      );
    }
  }

  /// Update the edited proposal
  void updateProposal(ExplanationProposal updatedProposal) {
    state = state.copyWith(editedProposal: updatedProposal);
  }

  /// Update title
  void updateTitle(String title) {
    if (state.proposal == null) return;

    final current = state.editedProposal ?? state.proposal!;
    final updated = ExplanationProposal(
      title: title,
      summary: current.summary,
      keyPoints: current.keyPoints,
      content: current.content,
    );
    state = state.copyWith(editedProposal: updated);
  }

  /// Update summary
  void updateSummary(String summary) {
    if (state.proposal == null) return;

    final current = state.editedProposal ?? state.proposal!;
    final updated = ExplanationProposal(
      title: current.title,
      summary: summary,
      keyPoints: current.keyPoints,
      content: current.content,
    );
    state = state.copyWith(editedProposal: updated);
  }

  /// Update content
  void updateContent(String content) {
    if (state.proposal == null) return;

    final current = state.editedProposal ?? state.proposal!;
    final updated = ExplanationProposal(
      title: current.title,
      summary: current.summary,
      keyPoints: current.keyPoints,
      content: content,
    );
    state = state.copyWith(editedProposal: updated);
  }

  /// Update key points
  void updateKeyPoints(List<String> keyPoints) {
    if (state.proposal == null) return;

    final current = state.editedProposal ?? state.proposal!;
    final updated = ExplanationProposal(
      title: current.title,
      summary: current.summary,
      keyPoints: keyPoints,
      content: current.content,
    );
    state = state.copyWith(editedProposal: updated);
  }

  /// Save explanation to a study set
  Future<void> saveExplanation({
    required String studySetId,
    String? sourceImageUrl,
  }) async {
    try {
      state = state.copyWith(isSaving: true, error: null);

      if (state.proposal == null) {
        throw Exception('No explanation to save');
      }

      final current = state.currentProposal;

      final doc = ExplanationDoc(
        id: _uuid.v4(),
        studySetId: studySetId,
        title: current.title,
        summary: current.summary,
        keyPoints: current.keyPoints,
        content: current.content,
        sourceImageUrl: sourceImageUrl,
        createdAt: DateTime.now(),
      );

      await _localDataSource.saveExplanationDoc(doc);

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
    state = const ExplanationGenerationState();
  }
}
