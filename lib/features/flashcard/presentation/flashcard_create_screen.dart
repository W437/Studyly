import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/flashcard.dart';
import '../../../core/providers/study_providers.dart';
import '../../../ui/theme/color_tokens.dart';
import '../../../ui/widgets/app_buttons.dart';
import '../../../ui/widgets/filled_text_field.dart';

class FlashcardCreateScreen extends ConsumerStatefulWidget {
  const FlashcardCreateScreen({
    super.key,
    required this.studySetId,
  });

  final String studySetId;

  static const routeName = 'flashcard-create';
  static const routePath = '/study-set/:id/flashcard/create';

  @override
  ConsumerState<FlashcardCreateScreen> createState() =>
      _FlashcardCreateScreenState();
}

class _FlashcardCreateScreenState extends ConsumerState<FlashcardCreateScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // AI Generation tab controllers
  final _aiContentController = TextEditingController();
  bool _isGenerating = false;
  List<Map<String, dynamic>> _generatedFlashcards = [];

  // Manual creation tab controllers
  final _manualFrontController = TextEditingController();
  final _manualBackController = TextEditingController();
  final _manualHintController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _aiContentController.dispose();
    _manualFrontController.dispose();
    _manualBackController.dispose();
    _manualHintController.dispose();
    super.dispose();
  }

  Future<void> _generateFlashcards() async {
    if (_aiContentController.text.trim().isEmpty) {
      _showError('Please enter some text or a link');
      return;
    }

    setState(() {
      _isGenerating = true;
      _generatedFlashcards = [];
    });

    try {
      final supabase = Supabase.instance.client;

      final response = await supabase.functions.invoke(
        'ai_generate_flashcards',
        body: {
          'content': _aiContentController.text.trim(),
        },
      );

      if (response.status != 200) {
        throw Exception(response.data['error'] ?? 'Failed to generate flashcards');
      }

      final flashcards = (response.data['flashcards'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();

      setState(() {
        _generatedFlashcards = flashcards;
        _isGenerating = false;
      });

      if (flashcards.isEmpty) {
        _showError('No flashcards were generated. Please try different content.');
      }
    } catch (e) {
      setState(() => _isGenerating = false);
      _showError('Failed to generate flashcards: ${e.toString()}');
    }
  }

  Future<void> _saveGeneratedFlashcards() async {
    if (_generatedFlashcards.isEmpty) return;

    try {
      final repository = ref.read(studyRepositoryProvider);
      const uuid = Uuid();

      for (final data in _generatedFlashcards) {
        final flashcard = Flashcard(
          id: uuid.v4(),
          studySetId: widget.studySetId,
          front: data['front'] as String,
          back: data['back'] as String,
          hint: data['hint'] as String?,
          difficulty: 0,
          createdAt: DateTime.now(),
          srsState: null, // Will be initialized on first review
        );

        await repository.updateFlashcard(flashcard);
      }

      if (mounted) {
        HapticFeedback.lightImpact();
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_generatedFlashcards.length} flashcards added successfully',
            ),
          ),
        );
      }
    } catch (e) {
      _showError('Failed to save flashcards: ${e.toString()}');
    }
  }

  Future<void> _saveManualFlashcard() async {
    if (_manualFrontController.text.trim().isEmpty ||
        _manualBackController.text.trim().isEmpty) {
      _showError('Please fill in both question and answer');
      return;
    }

    try {
      final repository = ref.read(studyRepositoryProvider);
      const uuid = Uuid();

      final flashcard = Flashcard(
        id: uuid.v4(),
        studySetId: widget.studySetId,
        front: _manualFrontController.text.trim(),
        back: _manualBackController.text.trim(),
        hint: _manualHintController.text.trim().isEmpty
            ? null
            : _manualHintController.text.trim(),
        difficulty: 0,
        createdAt: DateTime.now(),
        srsState: null,
      );

      await repository.updateFlashcard(flashcard);

      if (mounted) {
        HapticFeedback.lightImpact();
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Flashcard added successfully')),
        );
      }
    } catch (e) {
      _showError('Failed to save flashcard: ${e.toString()}');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: StudyColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Flashcards'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'AI Generate'),
            Tab(text: 'Manual Create'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAIGenerateTab(),
          _buildManualCreateTab(),
        ],
      ),
    );
  }

  Widget _buildAIGenerateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Paste text or a link',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8.0),
          Text(
            'Our AI will automatically generate flashcards from your content',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: StudyColors.textSecondary,
                ),
          ),
          const SizedBox(height: 16.0),
          FilledTextField(
            controller: _aiContentController,
            hint: 'Paste your text or link here...',
            maxLines: 10,
          ),
          const SizedBox(height: 16.0),
          PrimaryButton(
            label: _isGenerating ? 'Generating...' : 'Generate Flashcards',
            onPressed: _isGenerating ? null : _generateFlashcards,
            leading: _isGenerating
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : null,
          ),
          if (_generatedFlashcards.isNotEmpty) ...[
            const SizedBox(height: 24.0),
            Text(
              'Generated Flashcards (${_generatedFlashcards.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8.0),
            ..._generatedFlashcards.asMap().entries.map((entry) {
              final index = entry.key;
              final flashcard = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Card ${index + 1}',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: StudyColors.textSecondary,
                                  ),
                        ),
                        const SizedBox(height: 8.0),
                        Text(
                          'Q: ${flashcard['front']}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8.0),
                        Text(
                          'A: ${flashcard['back']}',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: StudyColors.textSecondary,
                                  ),
                        ),
                        if (flashcard['hint'] != null) ...[
                          const SizedBox(height: 8.0),
                          Text(
                            'Hint: ${flashcard['hint']}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: StudyColors.primary,
                                  fontStyle: FontStyle.italic,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 16.0),
            PrimaryButton(
              label: 'Save All Flashcards',
              onPressed: _saveGeneratedFlashcards,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildManualCreateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create a flashcard manually',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8.0),
          Text(
            'Enter the question, answer, and an optional hint',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: StudyColors.textSecondary,
                ),
          ),
          const SizedBox(height: 16.0),
          Text(
            'Question (Front)',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8.0),
          FilledTextField(
            controller: _manualFrontController,
            hint: 'Enter the question...',
            maxLines: 3,
          ),
          const SizedBox(height: 16.0),
          Text(
            'Answer (Back)',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8.0),
          FilledTextField(
            controller: _manualBackController,
            hint: 'Enter the answer...',
            maxLines: 3,
          ),
          const SizedBox(height: 16.0),
          Text(
            'Hint (Optional)',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8.0),
          FilledTextField(
            controller: _manualHintController,
            hint: 'Enter a hint (optional)...',
            maxLines: 2,
          ),
          const SizedBox(height: 24.0),
          PrimaryButton(
            label: 'Add Flashcard',
            onPressed: _saveManualFlashcard,
          ),
        ],
      ),
    );
  }
}
