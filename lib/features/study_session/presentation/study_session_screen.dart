import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/study_content_type.dart';
import '../../../core/models/study_document.dart';
import '../../../core/providers/study_providers.dart';
import '../../../ui/theme/color_tokens.dart';
import '../../../ui/theme/spacing.dart';

class StudySessionScreen extends ConsumerStatefulWidget {
  const StudySessionScreen({super.key});

  @override
  ConsumerState<StudySessionScreen> createState() => _StudySessionScreenState();
}

class _StudySessionScreenState extends ConsumerState<StudySessionScreen> {
  int _selectedTab = 1; // Explanations selected by default

  StudyContentType get _selectedContentType {
    switch (_selectedTab) {
      case 0:
        return StudyContentType.flashcards;
      case 1:
        return StudyContentType.explanations;
      case 2:
        return StudyContentType.exercises;
      default:
        return StudyContentType.explanations;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final documentsAsync = ref.watch(
      studyDocumentsProvider(_selectedContentType),
    );

    return Column(
      children: [
        // Tab Selector
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: StudySpacing.lg),
            children: [
              _TabChip(
                label: 'Flashcards',
                isSelected: _selectedTab == 0,
                onTap: () => setState(() => _selectedTab = 0),
              ),
              const SizedBox(width: 12),
              _TabChip(
                label: 'Explanations',
                isSelected: _selectedTab == 1,
                onTap: () => setState(() => _selectedTab = 1),
              ),
              const SizedBox(width: 12),
              _TabChip(
                label: 'Exercises',
                isSelected: _selectedTab == 2,
                onTap: () => setState(() => _selectedTab = 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: StudySpacing.lg),

        // Documents List
        Expanded(
          child: documentsAsync.when(
            data: (documents) {
              if (documents.isEmpty) {
                return const _EmptyDocumentState();
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: StudySpacing.lg,
                ),
                itemCount: documents.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: StudySpacing.md),
                itemBuilder: (context, index) {
                  final document = documents[index];
                  return _DocumentCard(document: document);
                },
              );
            },
            loading: () => ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: StudySpacing.lg),
              itemCount: 4,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: StudySpacing.md),
              itemBuilder: (_, __) => const _DocumentSkeleton(),
            ),
            error: (error, stack) => const _DocumentErrorState(),
          ),
        ),

        // Bottom Action Bar
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: StudySpacing.lg,
            vertical: StudySpacing.md,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ActionButton(
                  icon: Icons.sort,
                  label: 'Sort',
                  onPressed: () {},
                ),
                const SizedBox(width: 24),
                _ActionButton(
                  icon: Icons.tune,
                  label: 'Filter',
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? StudyColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? StudyColors.primary : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isSelected ? Colors.white : StudyColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.document});

  final StudyDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = _iconForDocumentType(document.type);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(StudySpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: StudyColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 24, color: StudyColors.textPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: StudyColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${document.sizeLabel}  ·  ${document.source}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: StudyColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: StudySpacing.md),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: StudyColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  document.category.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: StudyColors.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.more_vert,
                size: 20,
                color: StudyColors.textTertiary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DocumentSkeleton extends StatelessWidget {
  const _DocumentSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

class _EmptyDocumentState extends StatelessWidget {
  const _EmptyDocumentState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(StudySpacing.lg),
        child: Text(
          'No materials available under this category yet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: StudyColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _DocumentErrorState extends StatelessWidget {
  const _DocumentErrorState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(StudySpacing.lg),
        child: Text(
          'Unable to load study materials. Please try again soon.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFFB00020),
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

IconData _iconForDocumentType(StudyContentType type) {
  switch (type) {
    case StudyContentType.flashcards:
      return Icons.style;
    case StudyContentType.explanations:
      return Icons.menu_book_outlined;
    case StudyContentType.exercises:
      return Icons.task_outlined;
    case StudyContentType.studySets:
      return Icons.layers_outlined;
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: StudyColors.textPrimary),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: StudyColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
