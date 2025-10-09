import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/routes.dart';
import '../../../core/models/study_content_type.dart';
import '../../../core/models/study_plan_task.dart';
import '../../../core/models/study_set.dart';
import '../../../core/providers/study_providers.dart';
import '../../../ui/theme/color_tokens.dart';
import '../../../ui/theme/spacing.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late final List<DateTime> _dateRange;
  late final DateTime _today;
  late DateTime _selectedDate;
  late final ScrollController _scrollController;
  bool _hasScrolledToToday = false;

  @override
  void initState() {
    super.initState();
    _today = _normalize(DateTime.now());
    _selectedDate = _today;
    final startDate = _today.subtract(const Duration(days: 14));
    _dateRange = List.generate(
      29,
      (index) => startDate.add(Duration(days: index)),
    );

    // Calculate initial scroll position to center today
    final todayIndex = _dateRange.indexWhere((date) => _isSameDay(date, _today));
    final itemWidth = 72.0;

    // Use initialScrollOffset to position without animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasScrolledToToday && _scrollController.hasClients) {
        final screenWidth = MediaQuery.of(context).size.width;
        final offset = (todayIndex * itemWidth) - (screenWidth / 2) + (itemWidth / 2);
        _scrollController.jumpTo(
          offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        );
        _hasScrolledToToday = true;
      }
    });

    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasksAsync = ref.watch(studyTasksProvider(_selectedDate));
    final studySetsAsync = ref.watch(studySetsProvider);

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: StudySpacing.lg,
            vertical: 0,
          ),
          children: [
            const SizedBox(height: StudySpacing.md),
            // Premium Upgrade Card
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4DB6AC), Color(0xFF80CBC4)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Upgrade Premium!',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Enjoy all the benefits',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Upgrade',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: StudyColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 80),
                    ],
                  ),
                ),
                Positioned(
                  right: 20,
                  top: -25,
                  child: Transform.rotate(
                    angle: -0.3,
                    child: const Text('👑', style: TextStyle(fontSize: 96)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: StudySpacing.md),

            // Recent Study Sets
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Study Sets',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: StudyColors.textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: Row(
                    children: const [
                      Text(
                        'View All',
                        style: TextStyle(
                          color: StudyColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward,
                        size: 18,
                        color: StudyColors.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: StudySpacing.md),

            // Study Set Card
            _FeaturedStudySetCard(studySetsAsync: studySetsAsync),
            const SizedBox(height: StudySpacing.xl),

            // Week Calendar
            SizedBox(
              height: 90,
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                itemCount: _dateRange.length,
                itemBuilder: (context, index) {
                  final date = _dateRange[index];
                  return _DateItem(
                    date: date,
                    isToday: _isSameDay(date, _today),
                    isSelected: _isSameDay(date, _selectedDate),
                    onTap: () {
                      setState(() {
                        _selectedDate = _normalize(date);
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: StudySpacing.xl),

            // Your study plan today
            _TaskSection(tasksAsync: tasksAsync),
            const SizedBox(height: 100), // Extra space for FAB
          ],
        ),
        // Floating Chat Button
        Positioned(
          right: StudySpacing.lg,
          bottom: 16, // Just above bottom nav
          child: FloatingActionButton(
            backgroundColor: StudyColors.primary,
            shape: const CircleBorder(),
            onPressed: () {
              context.go(AppRoute.chat.path);
            },
            child: const Icon(
              Icons.chat_bubble_outline,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ],
    );
  }

  DateTime _normalize(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _DateItem extends StatelessWidget {
  const _DateItem({
    required this.date,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime date;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  static const _weekdayLabels = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayText = date.day.toString();
    final label = _weekdayLabels[date.weekday - 1];
    final Color dayColor = isSelected
        ? StudyColors.primary
        : (isToday ? StudyColors.textPrimary : StudyColors.textSecondary);
    final Color labelColor = isSelected
        ? StudyColors.primary
        : StudyColors.textTertiary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(vertical: StudySpacing.sm),
        decoration: BoxDecoration(
          color: isSelected
              ? StudyColors.primary.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              dayText,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: dayColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: labelColor,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 6),
            if (isToday)
              Container(
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                  color: isSelected
                      ? StudyColors.primary
                      : StudyColors.primary.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              )
            else
              const SizedBox(height: 3),
          ],
        ),
      ),
    );
  }
}

class _TaskSection extends StatelessWidget {
  const _TaskSection({required this.tasksAsync});

  final AsyncValue<List<StudyPlanTask>> tasksAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return tasksAsync.when(
      data: (tasks) {
        final completed = tasks.where((task) => task.isCompleted).length;
        final total = tasks.length;
        final title = total > 0
            ? 'Your study plan today ($completed/$total)'
            : 'Your study plan today';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: StudyColors.textPrimary,
              ),
            ),
            const SizedBox(height: StudySpacing.lg),
            if (total == 0)
              const _TaskEmptyState()
            else ...[
              for (var i = 0; i < tasks.length; i++) ...[
                _TaskItem(task: tasks[i]),
                if (i < tasks.length - 1)
                  const SizedBox(height: StudySpacing.md),
              ],
            ],
          ],
        );
      },
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _TaskSectionTitle(),
          SizedBox(height: StudySpacing.lg),
          _TaskSkeleton(),
          SizedBox(height: StudySpacing.md),
          _TaskSkeleton(),
        ],
      ),
      error: (error, stack) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TaskSectionTitle(),
          SizedBox(height: StudySpacing.lg),
          _TaskErrorNotice(),
        ],
      ),
    );
  }
}

class _TaskSectionTitle extends StatelessWidget {
  const _TaskSectionTitle();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Your study plan today',
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: StudyColors.textPrimary,
      ),
    );
  }
}

class _TaskItem extends StatelessWidget {
  const _TaskItem({required this.task});

  final StudyPlanTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = _iconForContentType(task.contentType);

    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: StudyColors.primary, width: 2),
            color: task.isCompleted ? StudyColors.primary : Colors.transparent,
          ),
          child: task.isCompleted
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : null,
        ),
        const SizedBox(width: StudySpacing.md),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: StudyColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: StudyColors.textSecondary),
        ),
        const SizedBox(width: StudySpacing.md),
        Expanded(
          child: Text(
            task.title,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: StudyColors.textPrimary,
              fontWeight: task.isCompleted ? FontWeight.w500 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _TaskSkeleton extends StatelessWidget {
  const _TaskSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade300, width: 2),
          ),
        ),
        const SizedBox(width: StudySpacing.md),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(width: StudySpacing.md),
        Expanded(
          child: Container(
            height: 16,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}

class _TaskEmptyState extends StatelessWidget {
  const _TaskEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(StudySpacing.lg),
      decoration: BoxDecoration(
        color: StudyColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'Nothing scheduled for this day. Enjoy a lighter study load!',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: StudyColors.textSecondary,
        ),
      ),
    );
  }
}

class _TaskErrorNotice extends StatelessWidget {
  const _TaskErrorNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(StudySpacing.lg),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE5E5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'Unable to load today\'s plan. Please try again soon.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: const Color(0xFFB00020),
        ),
      ),
    );
  }
}

class _FeaturedStudySetCard extends StatelessWidget {
  const _FeaturedStudySetCard({required this.studySetsAsync});

  final AsyncValue<List<StudySet>> studySetsAsync;

  @override
  Widget build(BuildContext context) {
    return studySetsAsync.when(
      data: (sets) {
        if (sets.isEmpty) {
          return const _StudySetEmptyState();
        }
        return _StudySetOverviewCard(studySet: sets.first);
      },
      loading: () => const _StudySetSkeleton(),
      error: (error, stack) => const _StudySetErrorNotice(),
    );
  }
}

class _StudySetOverviewCard extends StatelessWidget {
  const _StudySetOverviewCard({required this.studySet});

  final StudySet studySet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = studySet.totalItems;
    final progress = total == 0
        ? 0.0
        : (studySet.flashcards / total).clamp(0.0, 1.0);
    final progressLabel = '${(progress * 100).round()}%';
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
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(StudySpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    studySet.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: StudyColors.textPrimary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 3,
                          backgroundColor: StudyColors.surfaceVariant,
                          valueColor: AlwaysStoppedAnimation(borderColor),
                        ),
                      ),
                      Text(
                        progressLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: StudyColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: StudySpacing.sm),
            Text(
              '${studySet.flashcards} flashcards  ·  ${studySet.explanations} explanations  ·  ${studySet.exercises} exercises',
              style: const TextStyle(
                fontSize: 12,
                color: StudyColors.textSecondary,
              ),
            ),
            const SizedBox(height: StudySpacing.md),
            Text(
              studySet.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: StudyColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: StudySpacing.lg),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: StudySpacing.md,
                    vertical: StudySpacing.sm,
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

class _StudySetSkeleton extends StatelessWidget {
  const _StudySetSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

class _StudySetEmptyState extends StatelessWidget {
  const _StudySetEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(StudySpacing.lg),
      decoration: BoxDecoration(
        color: StudyColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'No featured study sets yet. Create one to fill this space!',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: StudyColors.textSecondary,
        ),
      ),
    );
  }
}

class _StudySetErrorNotice extends StatelessWidget {
  const _StudySetErrorNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(StudySpacing.lg),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE5E5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'Unable to load featured study sets.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: const Color(0xFFB00020),
        ),
      ),
    );
  }
}

IconData _iconForContentType(StudyContentType type) {
  switch (type) {
    case StudyContentType.flashcards:
      return Icons.style;
    case StudyContentType.explanations:
      return Icons.menu_book_outlined;
    case StudyContentType.exercises:
      return Icons.task_alt_outlined;
    case StudyContentType.studySets:
      return Icons.layers_outlined;
  }
}
