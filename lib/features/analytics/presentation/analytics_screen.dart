import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/study_set.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/models/study_content_type.dart';
import '../../../ui/theme/color_tokens.dart';
import '../../../ui/theme/spacing.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _selectedTab = 0;

  List<StudySet> _sortedStudySets(List<StudySet> sets) {
    switch (_selectedTab) {
      case 1:
        sets.sort((a, b) => b.flashcards.compareTo(a.flashcards));
        break;
      case 2:
        sets.sort((a, b) => b.explanations.compareTo(a.explanations));
        break;
      default:
        sets.sort(
          (a, b) => _viewsToDouble(b.views).compareTo(_viewsToDouble(a.views)),
        );
        break;
    }
    return sets;
  }

  double _viewsToDouble(String views) {
    final sanitized = views.trim().toLowerCase();
    if (sanitized.endsWith('k')) {
      final value = double.tryParse(sanitized.replaceAll('k', '')) ?? 0;
      return value * 1000;
    }
    if (sanitized.endsWith('m')) {
      final value = double.tryParse(sanitized.replaceAll('m', '')) ?? 0;
      return value * 1000000;
    }
    return double.tryParse(sanitized) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final studySetsAsync = ref.watch(studySetsProvider);

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
                label: 'Study Sets',
                isSelected: _selectedTab == 0,
                onTap: () => setState(() => _selectedTab = 0),
              ),
              const SizedBox(width: 12),
              _TabChip(
                label: 'Flashcards',
                isSelected: _selectedTab == 1,
                onTap: () => setState(() => _selectedTab = 1),
              ),
              const SizedBox(width: 12),
              _TabChip(
                label: 'Explanations',
                isSelected: _selectedTab == 2,
                onTap: () => setState(() => _selectedTab = 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: StudySpacing.lg),

        // Study Sets List
        Expanded(
          child: studySetsAsync.when(
            data: (sets) {
              final sortedSets = _sortedStudySets([...sets]);
              if (sortedSets.isEmpty) {
                return const _EmptyStudySetState();
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: StudySpacing.lg,
                ),
                itemCount: sortedSets.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: StudySpacing.md),
                itemBuilder: (context, index) {
                  final studySet = sortedSets[index];
                  return _AnalyticsStudySetCard(studySet: studySet);
                },
              );
            },
            loading: () => const _EmptyStudySetState(),
            error: (error, stack) => const _EmptyStudySetState(),
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

class _AnalyticsStudySetCard extends StatelessWidget {
  const _AnalyticsStudySetCard({required this.studySet});

  final StudySet studySet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = Color(studySet.borderColor);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        context.go('/study-set/${studySet.id}');
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: borderColor, width: 4)),
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
            Text(
              studySet.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: StudyColors.textPrimary,
              ),
            ),
            const SizedBox(height: StudySpacing.sm),
            Text(
              '${studySet.flashcards} flashcards  ·  ${studySet.explanations} explanations  ·  ${studySet.exercises} exercises',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: StudyColors.textSecondary,
              ),
            ),
            const SizedBox(height: StudySpacing.lg),
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_library,
                        size: 16,
                        color: StudyColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        studySet.tag.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: StudyColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  studySet.views,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: StudyColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(
                  Icons.more_vert,
                  size: 20,
                  color: StudyColors.textTertiary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsStudySetSkeleton extends StatelessWidget {
  const _AnalyticsStudySetSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

class _EmptyStudySetState extends StatelessWidget {
  const _EmptyStudySetState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(StudySpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 24),
            Text(
              'No Study Sets',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Create study sets to see\nyour analytics here',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudySetErrorState extends StatelessWidget {
  const _StudySetErrorState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(StudySpacing.lg),
        child: Text(
          'We couldn\'t load study analytics right now.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFFB00020),
          ),
        ),
      ),
    );
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
