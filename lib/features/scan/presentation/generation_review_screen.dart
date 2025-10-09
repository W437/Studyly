import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/generation_result.dart';
import '../../../core/providers/scan_providers.dart';
import '../../../core/providers/study_providers.dart';
import 'widgets/exercise_review_widget.dart';
import 'widgets/explanation_review_widget.dart';
import 'widgets/flashcard_review_widget.dart';

class GenerationReviewScreen extends ConsumerStatefulWidget {
  const GenerationReviewScreen({
    required this.scannedItemId,
    required this.type,
    this.subject,
    this.level,
    super.key,
  });

  final String scannedItemId;
  final GenerationType type;
  final String? subject;
  final String? level;

  @override
  ConsumerState<GenerationReviewScreen> createState() =>
      _GenerationReviewScreenState();
}

class _GenerationReviewScreenState
    extends ConsumerState<GenerationReviewScreen> {
  String? _selectedStudySetId;

  @override
  void initState() {
    super.initState();
    // Load the scanned item
    Future.microtask(() {
      ref
          .read(scanControllerProvider.notifier)
          .loadScannedItem(widget.scannedItemId);
    });
  }

  String _getTitle() {
    switch (widget.type) {
      case GenerationType.flashcards:
        return 'Review Flashcards';
      case GenerationType.explanation:
        return 'Review Explanation';
      case GenerationType.exercise:
        return 'Review Exercises';
      case GenerationType.chatSolve:
        return 'Review Chat Solution';
    }
  }

  Future<void> _save() async {
    if (_selectedStudySetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a study set'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      switch (widget.type) {
        case GenerationType.flashcards:
          await ref
              .read(flashcardGenerationControllerProvider.notifier)
              .saveFlashcards(studySetId: _selectedStudySetId!);
          break;
        case GenerationType.explanation:
          final scanState = ref.read(scanControllerProvider);
          await ref
              .read(explanationGenerationControllerProvider.notifier)
              .saveExplanation(
                studySetId: _selectedStudySetId!,
                sourceImageUrl: scanState.currentItem?.remoteImageUrl,
              );
          break;
        case GenerationType.exercise:
          await ref
              .read(exerciseGenerationControllerProvider.notifier)
              .saveExercises(studySetId: _selectedStudySetId!);
          break;
        case GenerationType.chatSolve:
          // Not implemented yet
          break;
      }

      // Mark scanned item as completed
      await ref
          .read(scanControllerProvider.notifier)
          .markCompleted(widget.scannedItemId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate back to library or study set detail
        context.pop();
        context.pop();
        context.pop();
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(scanControllerProvider);
    final studySetsAsync = ref.watch(studySetsProvider);

    final scannedItem = scanState.currentItem;

    if (scanState.isLoading || scannedItem == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_getTitle()),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_getTitle()),
        actions: [
          if (widget.subject != null || widget.level != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  if (widget.subject != null)
                    Chip(
                      label: Text(widget.subject!),
                      backgroundColor: Colors.blue[100],
                    ),
                  if (widget.level != null) ...[
                    const SizedBox(width: 4),
                    Chip(
                      label: Text(widget.level!),
                      backgroundColor: Colors.green[100],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Main content (adaptive based on type)
          Expanded(
            child: _buildContentForType(scannedItem),
          ),

          // Bottom bar with study set selector and save button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Study set dropdown
                  studySetsAsync.when(
                    data: (studySets) {
                      return DropdownButtonFormField<String>(
                        value: _selectedStudySetId,
                        decoration: const InputDecoration(
                          labelText: 'Select Study Set',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.folder),
                        ),
                        items: [
                          // Existing study sets
                          ...studySets.map((set) {
                            return DropdownMenuItem(
                              value: set.id,
                              child: Text(set.title),
                            );
                          }),
                          // Create new option
                          const DropdownMenuItem(
                            value: 'create_new',
                            child: Row(
                              children: [
                                Icon(Icons.add_circle_outline),
                                SizedBox(width: 8),
                                Text('Create New Study Set'),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == 'create_new') {
                            // TODO: Show dialog to create new study set
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Create new study set feature coming soon!',
                                ),
                              ),
                            );
                          } else {
                            setState(() {
                              _selectedStudySetId = value;
                            });
                          }
                        },
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (err, stack) => Text(
                      'Error loading study sets: $err',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Save button
                  ElevatedButton(
                    onPressed: _isSaveEnabled() ? _save : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving()
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save to Study Set'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentForType(scannedItem) {
    switch (widget.type) {
      case GenerationType.flashcards:
        return FlashcardReviewWidget(
          scannedItem: scannedItem,
          subject: widget.subject,
          level: widget.level,
        );
      case GenerationType.explanation:
        return ExplanationReviewWidget(
          scannedItem: scannedItem,
          subject: widget.subject,
          level: widget.level,
        );
      case GenerationType.exercise:
        return ExerciseReviewWidget(
          scannedItem: scannedItem,
          subject: widget.subject,
          level: widget.level,
        );
      case GenerationType.chatSolve:
        return const Center(
          child: Text('Chat solve feature coming soon!'),
        );
    }
  }

  bool _isSaveEnabled() {
    if (_selectedStudySetId == null) return false;
    if (_isSaving()) return false;

    switch (widget.type) {
      case GenerationType.flashcards:
        final state = ref.watch(flashcardGenerationControllerProvider);
        return !state.isGenerating &&
            state.error == null &&
            state.selectedIndices.isNotEmpty;
      case GenerationType.explanation:
        final state = ref.watch(explanationGenerationControllerProvider);
        return !state.isGenerating && state.error == null && state.proposal != null;
      case GenerationType.exercise:
        final state = ref.watch(exerciseGenerationControllerProvider);
        return !state.isGenerating &&
            state.error == null &&
            state.selectedIndices.isNotEmpty;
      case GenerationType.chatSolve:
        return false;
    }
  }

  bool _isSaving() {
    switch (widget.type) {
      case GenerationType.flashcards:
        return ref.watch(flashcardGenerationControllerProvider).isSaving;
      case GenerationType.explanation:
        return ref.watch(explanationGenerationControllerProvider).isSaving;
      case GenerationType.exercise:
        return ref.watch(exerciseGenerationControllerProvider).isSaving;
      case GenerationType.chatSolve:
        return false;
    }
  }
}
