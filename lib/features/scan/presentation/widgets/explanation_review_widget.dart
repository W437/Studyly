import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/scanned_item.dart';
import '../../../../core/providers/scan_providers.dart';

class ExplanationReviewWidget extends ConsumerStatefulWidget {
  const ExplanationReviewWidget({
    required this.scannedItem,
    this.subject,
    this.level,
    super.key,
  });

  final ScannedItem scannedItem;
  final String? subject;
  final String? level;

  @override
  ConsumerState<ExplanationReviewWidget> createState() =>
      _ExplanationReviewWidgetState();
}

class _ExplanationReviewWidgetState
    extends ConsumerState<ExplanationReviewWidget> {
  final _titleController = TextEditingController();
  final _summaryController = TextEditingController();
  final _contentController = TextEditingController();
  final _keyPointControllers = <TextEditingController>[];
  bool _showPreview = false;

  @override
  void initState() {
    super.initState();
    _generateExplanation();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _summaryController.dispose();
    _contentController.dispose();
    for (final controller in _keyPointControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _generateExplanation() async {
    await ref
        .read(explanationGenerationControllerProvider.notifier)
        .generateExplanation(
          scannedItem: widget.scannedItem,
          subject: widget.subject,
          level: widget.level,
        );
  }

  void _updateControllersFromState() {
    final state = ref.read(explanationGenerationControllerProvider);
    if (state.proposal != null) {
      final current = state.currentProposal;

      if (_titleController.text.isEmpty) {
        _titleController.text = current.title;
      }
      if (_summaryController.text.isEmpty) {
        _summaryController.text = current.summary;
      }
      if (_contentController.text.isEmpty) {
        _contentController.text = current.content;
      }

      // Initialize key point controllers if empty
      if (_keyPointControllers.isEmpty && current.keyPoints.isNotEmpty) {
        for (final point in current.keyPoints) {
          final controller = TextEditingController(text: point);
          _keyPointControllers.add(controller);
        }
      }
    }
  }

  void _addKeyPoint() {
    setState(() {
      _keyPointControllers.add(TextEditingController());
    });
  }

  void _removeKeyPoint(int index) {
    setState(() {
      _keyPointControllers[index].dispose();
      _keyPointControllers.removeAt(index);
    });
    _saveKeyPoints();
  }

  void _saveTitle() {
    ref
        .read(explanationGenerationControllerProvider.notifier)
        .updateTitle(_titleController.text);
  }

  void _saveSummary() {
    ref
        .read(explanationGenerationControllerProvider.notifier)
        .updateSummary(_summaryController.text);
  }

  void _saveContent() {
    ref
        .read(explanationGenerationControllerProvider.notifier)
        .updateContent(_contentController.text);
  }

  void _saveKeyPoints() {
    final keyPoints = _keyPointControllers
        .map((c) => c.text)
        .where((text) => text.isNotEmpty)
        .toList();
    ref
        .read(explanationGenerationControllerProvider.notifier)
        .updateKeyPoints(keyPoints);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(explanationGenerationControllerProvider);

    if (state.isGenerating) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Generating explanation...'),
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
              onPressed: _generateExplanation,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Update controllers when state changes
    _updateControllersFromState();

    return Column(
      children: [
        // Header with preview toggle
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Edit Explanation',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _showPreview ? Icons.edit : Icons.preview,
                ),
                onPressed: () {
                  setState(() {
                    _showPreview = !_showPreview;
                  });
                },
                tooltip: _showPreview ? 'Edit' : 'Preview',
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _showPreview ? _buildPreviewMode() : _buildEditMode(),
          ),
        ),
      ],
    );
  }

  Widget _buildEditMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          onChanged: (_) => _saveTitle(),
        ),
        const SizedBox(height: 16),

        // Summary
        TextField(
          controller: _summaryController,
          decoration: const InputDecoration(
            labelText: 'Summary',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
          onChanged: (_) => _saveSummary(),
        ),
        const SizedBox(height: 16),

        // Key Points
        Row(
          children: [
            Text(
              'Key Points',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _addKeyPoint,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._keyPointControllers.asMap().entries.map((entry) {
          final index = entry.key;
          final controller = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: 'Key point ${index + 1}',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _saveKeyPoints(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => _removeKeyPoint(index),
                  color: Colors.red,
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),

        // Content (Markdown)
        TextField(
          controller: _contentController,
          decoration: const InputDecoration(
            labelText: 'Content (Markdown)',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
            helperText: 'Supports markdown formatting',
          ),
          maxLines: 15,
          onChanged: (_) => _saveContent(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPreviewMode() {
    final state = ref.read(explanationGenerationControllerProvider);
    if (state.proposal == null) return const SizedBox.shrink();

    final current = state.currentProposal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Text(
          current.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),

        // Summary
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Text(
            current.summary,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 16),

        // Key Points
        if (current.keyPoints.isNotEmpty) ...[
          Text(
            'Key Points',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          ...current.keyPoints.map((point) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle, size: 20, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(child: Text(point)),
                  ],
                ),
              )),
          const SizedBox(height: 16),
        ],

        // Content
        Text(
          'Content',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(current.content),
        const SizedBox(height: 16),
      ],
    );
  }
}
