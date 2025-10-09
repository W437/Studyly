import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/scanned_item.dart';
import '../../../../core/providers/scan_providers.dart';
import '../../../../core/services/ai_generation_service.dart';

class ExerciseReviewWidget extends ConsumerStatefulWidget {
  const ExerciseReviewWidget({
    required this.scannedItem,
    this.subject,
    this.level,
    super.key,
  });

  final ScannedItem scannedItem;
  final String? subject;
  final String? level;

  @override
  ConsumerState<ExerciseReviewWidget> createState() =>
      _ExerciseReviewWidgetState();
}

class _ExerciseReviewWidgetState extends ConsumerState<ExerciseReviewWidget> {
  int? _editingIndex;
  final _questionController = TextEditingController();
  final _optionControllers = <TextEditingController>[];
  final _explanationController = TextEditingController();
  String _editingCorrectAnswer = '';
  int _editingDifficulty = 3;

  @override
  void initState() {
    super.initState();
    _generateExercises();
  }

  @override
  void dispose() {
    _questionController.dispose();
    _explanationController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _generateExercises() async {
    await ref.read(exerciseGenerationControllerProvider.notifier).generateExercises(
          scannedItem: widget.scannedItem,
          subject: widget.subject,
          level: widget.level,
          count: 5,
        );
  }

  void _startEditing(int index, ExerciseProposal proposal) {
    setState(() {
      _editingIndex = index;
      _questionController.text = proposal.question;
      _explanationController.text = proposal.explanation;
      _editingCorrectAnswer = proposal.correctAnswer;
      _editingDifficulty = proposal.difficulty;

      // Clear previous option controllers
      for (final controller in _optionControllers) {
        controller.dispose();
      }
      _optionControllers.clear();

      // Create controllers for each option
      for (final option in proposal.options) {
        _optionControllers.add(TextEditingController(text: option));
      }
    });
  }

  void _saveEdit() {
    if (_editingIndex == null) return;

    final updatedProposal = ExerciseProposal(
      question: _questionController.text,
      options: _optionControllers.map((c) => c.text).toList(),
      correctAnswer: _editingCorrectAnswer,
      explanation: _explanationController.text,
      difficulty: _editingDifficulty,
    );

    ref
        .read(exerciseGenerationControllerProvider.notifier)
        .updateProposal(_editingIndex!, updatedProposal);

    setState(() {
      _editingIndex = null;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(exerciseGenerationControllerProvider);

    if (state.isGenerating) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Generating practice questions...'),
          ],
        ),
      );
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: ${state.error}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _generateExercises,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final selectedCount = state.selectedIndices.length;
    final totalCount = state.proposals.length;

    return Column(
      children: [
        // Header with select all/deselect all
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Select exercises to keep',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              TextButton(
                onPressed: selectedCount == totalCount
                    ? ref
                        .read(exerciseGenerationControllerProvider.notifier)
                        .deselectAll
                    : ref
                        .read(exerciseGenerationControllerProvider.notifier)
                        .selectAll,
                child: Text(
                  selectedCount == totalCount ? 'Deselect All' : 'Select All',
                ),
              ),
            ],
          ),
        ),

        // List of exercise proposals
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: state.proposals.length,
            itemBuilder: (context, index) {
              final proposal = state.proposals[index];
              final isSelected = state.selectedIndices.contains(index);
              final isEditing = _editingIndex == index;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: isEditing
                      ? null
                      : () => ref
                          .read(exerciseGenerationControllerProvider.notifier)
                          .toggleSelection(index),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: isEditing
                        ? _buildEditingMode(proposal)
                        : _buildViewMode(index, proposal, isSelected),
                  ),
                ),
              );
            },
          ),
        ),

        // Count footer
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border(
              top: BorderSide(color: Colors.grey[300]!),
            ),
          ),
          child: Text(
            '$selectedCount of $totalCount selected',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildViewMode(int index, ExerciseProposal proposal, bool isSelected) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: isSelected,
          onChanged: (_) => ref
              .read(exerciseGenerationControllerProvider.notifier)
              .toggleSelection(index),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Question
              Text(
                'Q${index + 1}: ${proposal.question}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),

              // Options
              ...proposal.options.asMap().entries.map((entry) {
                final optionIndex = entry.key;
                final option = entry.value;
                final optionLetter = String.fromCharCode(65 + optionIndex); // A, B, C, D
                final isCorrect = proposal.correctAnswer == option;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isCorrect ? Colors.green[100] : Colors.grey[200],
                          border: Border.all(
                            color: isCorrect ? Colors.green : Colors.grey,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          optionLetter,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isCorrect ? Colors.green[900] : Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          option,
                          style: TextStyle(
                            fontWeight: isCorrect ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (isCorrect)
                        const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),

              // Explanation (collapsible)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Explanation',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.blue[700],
                        fontWeight: FontWeight.w600,
                      ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      proposal.explanation,
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),

              // Difficulty
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getDifficultyColor(proposal.difficulty),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _getDifficultyLabel(proposal.difficulty),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () => _startEditing(index, proposal),
        ),
      ],
    );
  }

  Widget _buildEditingMode(ExerciseProposal proposal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Question
        TextField(
          controller: _questionController,
          decoration: const InputDecoration(
            labelText: 'Question',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 12),

        // Options
        Text(
          'Options:',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        ..._optionControllers.asMap().entries.map((entry) {
          final optionIndex = entry.key;
          final controller = entry.value;
          final optionLetter = String.fromCharCode(65 + optionIndex);
          final isCorrect = _editingCorrectAnswer == controller.text;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Radio<String>(
                  value: controller.text,
                  groupValue: _editingCorrectAnswer,
                  onChanged: (value) {
                    setState(() {
                      _editingCorrectAnswer = value ?? '';
                    });
                  },
                ),
                Text(optionLetter),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: 'Option $optionLetter',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (newValue) {
                      if (isCorrect) {
                        setState(() {
                          _editingCorrectAnswer = newValue;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 12),

        // Explanation
        TextField(
          controller: _explanationController,
          decoration: const InputDecoration(
            labelText: 'Explanation',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 12),

        // Difficulty
        Row(
          children: [
            const Text('Difficulty: '),
            ...List.generate(
              5,
              (i) => IconButton(
                icon: Icon(
                  i < _editingDifficulty ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                ),
                onPressed: () {
                  setState(() {
                    _editingDifficulty = i + 1;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Actions
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _cancelEdit,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _saveEdit,
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }

  Color _getDifficultyColor(int difficulty) {
    if (difficulty <= 2) return Colors.green;
    if (difficulty <= 3) return Colors.orange;
    return Colors.red;
  }

  String _getDifficultyLabel(int difficulty) {
    if (difficulty <= 2) return 'Easy';
    if (difficulty <= 3) return 'Medium';
    return 'Hard';
  }
}
