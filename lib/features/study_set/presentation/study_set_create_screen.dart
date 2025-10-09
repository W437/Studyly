import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/study_content_type.dart';
import '../../../core/models/study_set.dart';
import '../../../core/providers/study_providers.dart';
import '../../../ui/theme/color_tokens.dart';
import '../../../ui/widgets/app_buttons.dart';
import '../../../ui/widgets/filled_text_field.dart';

class StudySetCreateScreen extends ConsumerStatefulWidget {
  const StudySetCreateScreen({super.key});

  static const routeName = 'study-set-create';
  static const routePath = '/study-set/create';

  @override
  ConsumerState<StudySetCreateScreen> createState() =>
      _StudySetCreateScreenState();
}

class _StudySetCreateScreenState extends ConsumerState<StudySetCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  StudyMaterialTag _selectedTag = StudyMaterialTag.biology;
  int _selectedColorIndex = 0;
  bool _isCreating = false;

  final List<Color> _borderColors = [
    const Color(0xFF6366F1), // Indigo
    const Color(0xFFEC4899), // Pink
    const Color(0xFF10B981), // Green
    const Color(0xFFF59E0B), // Amber
    const Color(0xFF8B5CF6), // Purple
    const Color(0xFF06B6D4), // Cyan
    const Color(0xFFEF4444), // Red
    const Color(0xFF14B8A6), // Teal
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createStudySet() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a title'),
          backgroundColor: StudyColors.error,
        ),
      );
      return;
    }

    if (_isCreating) return;

    setState(() => _isCreating = true);

    try {
      final repository = ref.read(studyRepositoryProvider);
      const uuid = Uuid();

      final studySet = StudySet(
        id: uuid.v4(),
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        flashcards: 0,
        explanations: 0,
        exercises: 0,
        views: '0',
        borderColor: _borderColors[_selectedColorIndex].value,
        tag: _selectedTag,
      );

      print('DEBUG: About to save study set: ${studySet.id}');
      await repository.saveStudySet(studySet);
      print('DEBUG: Study set saved successfully');

      if (mounted) {
        setState(() => _isCreating = false);
        HapticFeedback.lightImpact();
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Study set "${studySet.title}" created successfully'),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('DEBUG: Error creating study set: $e');
      print('DEBUG: Stack trace: $stackTrace');
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create study set: ${e.toString()}'),
            backgroundColor: StudyColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Study Set'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Text(
              'Study Set Details',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 24.0),

            // Title
            Text(
              'Title',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8.0),
            FilledTextField(
              controller: _titleController,
              hint: 'Enter study set title...',
              maxLines: 1,
            ),
            const SizedBox(height: 24.0),

            // Description
            Text(
              'Description',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8.0),
            FilledTextField(
              controller: _descriptionController,
              hint: 'Enter description...',
              maxLines: 4,
            ),
            const SizedBox(height: 24.0),

            // Category/Tag
            Text(
              'Category',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8.0),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: StudyMaterialTag.values.map((tag) {
                final isSelected = tag == _selectedTag;
                return GestureDetector(
                  onTap: () => setState(() => _selectedTag = tag),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 10.0,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? StudyColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(20.0),
                      border: Border.all(
                        color: isSelected
                            ? StudyColors.primary
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      tag.label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24.0),

            // Border Color
            Text(
              'Accent Color',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8.0),
            Wrap(
              spacing: 12.0,
              runSpacing: 12.0,
              children: _borderColors.asMap().entries.map((entry) {
                final index = entry.key;
                final color = entry.value;
                final isSelected = index == _selectedColorIndex;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColorIndex = index),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.black : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: isSelected
                        ? const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 24,
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32.0),

            // Create Button
            PrimaryButton(
              label: _isCreating ? 'Creating...' : 'Create Study Set',
              onPressed: _isCreating ? null : _createStudySet,
            ),
            const SizedBox(height: 16.0),
          ],
        ),
      ),
    );
  }
}
