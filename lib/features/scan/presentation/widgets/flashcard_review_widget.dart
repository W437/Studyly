import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/scanned_item.dart';
import '../../../../core/providers/scan_providers.dart';
import '../../../../core/services/ai_generation_service.dart';

class FlashcardReviewWidget extends ConsumerStatefulWidget {
  const FlashcardReviewWidget({
    required this.scannedItem,
    this.subject,
    this.level,
    super.key,
  });

  final ScannedItem scannedItem;
  final String? subject;
  final String? level;

  @override
  ConsumerState<FlashcardReviewWidget> createState() =>
      _FlashcardReviewWidgetState();
}

class _FlashcardReviewWidgetState
    extends ConsumerState<FlashcardReviewWidget> {
  int? _editingIndex;
  final _frontController = TextEditingController();
  final _backController = TextEditingController();
  final _hintController = TextEditingController();
  int _editingDifficulty = 3;

  @override
  void initState() {
    super.initState();
    _generateFlashcards();
  }

  @override
  void dispose() {
    _frontController.dispose();
    _backController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  Future<void> _generateFlashcards() async {
    await ref.read(flashcardGenerationControllerProvider.notifier).generateFlashcards(
          scannedItem: widget.scannedItem,
          subject: widget.subject,
          level: widget.level,
        );
  }

  void _startEditing(int index, FlashcardProposal proposal) {
    setState(() {
      _editingIndex = index;
      _frontController.text = proposal.front;
      _backController.text = proposal.back;
      _hintController.text = proposal.hint ?? '';
      _editingDifficulty = proposal.difficulty;
    });
  }

  void _saveEdit() {
    if (_editingIndex == null) return;

    final updatedProposal = FlashcardProposal(
      front: _frontController.text,
      back: _backController.text,
      hint: _hintController.text.isEmpty ? null : _hintController.text,
      difficulty: _editingDifficulty,
    );

    ref
        .read(flashcardGenerationControllerProvider.notifier)
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
    final state = ref.watch(flashcardGenerationControllerProvider);

    if (state.isGenerating) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Generating flashcards...'),
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
              onPressed: _generateFlashcards,
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
                  'Select flashcards to keep',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              TextButton(
                onPressed: selectedCount == totalCount
                    ? ref
                        .read(flashcardGenerationControllerProvider.notifier)
                        .deselectAll
                    : ref
                        .read(flashcardGenerationControllerProvider.notifier)
                        .selectAll,
                child: Text(
                  selectedCount == totalCount ? 'Deselect All' : 'Select All',
                ),
              ),
            ],
          ),
        ),

        // List of flashcard proposals
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
                          .read(flashcardGenerationControllerProvider.notifier)
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

  Widget _buildViewMode(int index, FlashcardProposal proposal, bool isSelected) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: isSelected,
          onChanged: (_) => ref
              .read(flashcardGenerationControllerProvider.notifier)
              .toggleSelection(index),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                proposal.front,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(proposal.back),
              if (proposal.hint != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Hint: ${proposal.hint}',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  ...List.generate(
                    5,
                    (i) => Icon(
                      i < proposal.difficulty
                          ? Icons.star
                          : Icons.star_border,
                      size: 16,
                      color: Colors.amber,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Difficulty: ${proposal.difficulty}/5',
                    style: Theme.of(context).textTheme.bodySmall,
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

  Widget _buildEditingMode(FlashcardProposal proposal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _frontController,
          decoration: const InputDecoration(
            labelText: 'Front (Question)',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _backController,
          decoration: const InputDecoration(
            labelText: 'Back (Answer)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _hintController,
          decoration: const InputDecoration(
            labelText: 'Hint (Optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
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
}
