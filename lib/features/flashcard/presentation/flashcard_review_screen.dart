import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/flashcard.dart';
import '../../../ui/theme/color_tokens.dart';
import '../../../ui/theme/spacing.dart';
import '../../../ui/widgets/app_buttons.dart';
import '../application/flashcard_review_controller.dart';

class FlashcardReviewScreen extends ConsumerStatefulWidget {
  const FlashcardReviewScreen({
    super.key,
    required this.studySetId,
  });

  final String studySetId;

  static const routeName = 'flashcard-review';
  static const routePath = '/study-set/:id/review';

  @override
  ConsumerState<FlashcardReviewScreen> createState() =>
      _FlashcardReviewScreenState();
}

class _FlashcardReviewScreenState
    extends ConsumerState<FlashcardReviewScreen> {
  @override
  void initState() {
    super.initState();
    // Start review session on init
    Future.microtask(() {
      ref
          .read(flashcardReviewControllerProvider.notifier)
          .startReviewSession(widget.studySetId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(flashcardReviewControllerProvider);

    return Scaffold(
      backgroundColor: StudyColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () {
            HapticFeedback.lightImpact();
            _showExitDialog(context);
          },
        ),
        title: state.isLoading
            ? null
            : Text(
                '${state.currentIndex + 1} / ${state.totalCards}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
        centerTitle: true,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
              ? _ErrorView(error: state.error!)
              : state.isCompleted
                  ? _CompletionView(
                      studySetId: widget.studySetId,
                      state: state,
                    )
                  : _ReviewView(
                      flashcard: state.currentCard!,
                      isFlipped: state.isFlipped,
                      totalCards: state.totalCards,
                      currentIndex: state.currentIndex,
                      onFlip: () {
                        HapticFeedback.selectionClick();
                        ref
                            .read(flashcardReviewControllerProvider.notifier)
                            .flipCard();
                      },
                      onAnswer: (difficulty) {
                        HapticFeedback.lightImpact();
                        ref
                            .read(flashcardReviewControllerProvider.notifier)
                            .answerCard(difficulty);
                      },
                    ),
    );
  }

  void _showExitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit Review?'),
        content: const Text(
          'Your progress will be saved, but you\'ll need to start this session again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.pop();
            },
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }
}

class _ReviewView extends StatefulWidget {
  const _ReviewView({
    required this.flashcard,
    required this.isFlipped,
    required this.totalCards,
    required this.currentIndex,
    required this.onFlip,
    required this.onAnswer,
  });

  final Flashcard flashcard;
  final bool isFlipped;
  final int totalCards;
  final int currentIndex;
  final VoidCallback onFlip;
  final void Function(int difficulty) onAnswer;

  @override
  State<_ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends State<_ReviewView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(_ReviewView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFlipped != widget.isFlipped) {
      if (widget.isFlipped) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
    // Reset animation on card change
    if (oldWidget.flashcard.id != widget.flashcard.id) {
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (widget.currentIndex) / widget.totalCards;

    return Column(
      children: [
        // Progress bar
        Container(
          height: 4,
          margin: const EdgeInsets.symmetric(
            horizontal: StudySpacing.lg,
            vertical: StudySpacing.sm,
          ),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: StudyColors.divider,
            valueColor: const AlwaysStoppedAnimation(StudyColors.primary),
          ),
        ),
        const SizedBox(height: StudySpacing.lg),

        // Flashcard
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: StudySpacing.lg),
            child: GestureDetector(
              onTap: widget.onFlip,
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  final angle = _animation.value * pi;
                  final isBack = angle > pi / 2;

                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(angle),
                    child: isBack
                        ? Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()..rotateY(pi),
                            child: _FlashcardSide(
                              content: widget.flashcard.back,
                              label: 'ANSWER',
                              isBack: true,
                            ),
                          )
                        : _FlashcardSide(
                            content: widget.flashcard.front,
                            label: 'QUESTION',
                            hint: widget.flashcard.hint,
                            isBack: false,
                          ),
                  );
                },
              ),
            ),
          ),
        ),

        const SizedBox(height: StudySpacing.lg),

        // Action buttons
        if (!widget.isFlipped)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: StudySpacing.lg),
            child: PrimaryButton(
              label: 'Show Answer',
              onPressed: widget.onFlip,
            ),
          )
        else
          _DifficultyButtons(onAnswer: widget.onAnswer),

        const SizedBox(height: StudySpacing.xl),
      ],
    );
  }
}

class _FlashcardSide extends StatelessWidget {
  const _FlashcardSide({
    required this.content,
    required this.label,
    required this.isBack,
    this.hint,
  });

  final String content;
  final String label;
  final String? hint;
  final bool isBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(StudySpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isBack ? StudyColors.primary : StudyColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: StudySpacing.lg),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Text(
                  content,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: StudyColors.textPrimary,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          if (hint != null && !isBack) ...[
            const SizedBox(height: StudySpacing.md),
            Container(
              padding: const EdgeInsets.all(StudySpacing.md),
              decoration: BoxDecoration(
                color: StudyColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: StudyColors.warning,
                  ),
                  const SizedBox(width: StudySpacing.sm),
                  Flexible(
                    child: Text(
                      hint!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: StudyColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DifficultyButtons extends StatelessWidget {
  const _DifficultyButtons({required this.onAnswer});

  final void Function(int difficulty) onAnswer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: StudySpacing.lg),
      child: Column(
        children: [
          const Text(
            'How well did you know this?',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: StudyColors.textSecondary,
            ),
          ),
          const SizedBox(height: StudySpacing.md),
          Row(
            children: [
              Expanded(
                child: _DifficultyButton(
                  label: 'Again',
                  color: StudyColors.error,
                  onPressed: () => onAnswer(1),
                ),
              ),
              const SizedBox(width: StudySpacing.sm),
              Expanded(
                child: _DifficultyButton(
                  label: 'Hard',
                  color: StudyColors.warning,
                  onPressed: () => onAnswer(2),
                ),
              ),
              const SizedBox(width: StudySpacing.sm),
              Expanded(
                child: _DifficultyButton(
                  label: 'Good',
                  color: StudyColors.primary,
                  onPressed: () => onAnswer(3),
                ),
              ),
              const SizedBox(width: StudySpacing.sm),
              Expanded(
                child: _DifficultyButton(
                  label: 'Easy',
                  color: StudyColors.success,
                  onPressed: () => onAnswer(4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DifficultyButton extends StatelessWidget {
  const _DifficultyButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: StudySpacing.md),
        elevation: 0,
        shadowColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CompletionView extends StatelessWidget {
  const _CompletionView({
    required this.studySetId,
    required this.state,
  });

  final String studySetId;
  final dynamic state;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(StudySpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: StudyColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                size: 48,
                color: StudyColors.success,
              ),
            ),
            const SizedBox(height: StudySpacing.lg),
            const Text(
              'Review Complete!',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: StudyColors.textPrimary,
              ),
            ),
            const SizedBox(height: StudySpacing.md),
            Text(
              'You reviewed ${state.totalCards} cards',
              style: const TextStyle(
                fontSize: 16,
                color: StudyColors.textSecondary,
              ),
            ),
            const SizedBox(height: StudySpacing.xl),
            PrimaryButton(
              label: 'Back to Study Set',
              onPressed: () {
                HapticFeedback.lightImpact();
                context.pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(StudySpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: StudyColors.error,
            ),
            const SizedBox(height: StudySpacing.lg),
            const Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: StudyColors.textPrimary,
              ),
            ),
            const SizedBox(height: StudySpacing.md),
            Text(
              error,
              style: const TextStyle(
                fontSize: 14,
                color: StudyColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: StudySpacing.xl),
            PrimaryButton(
              label: 'Go Back',
              onPressed: () {
                HapticFeedback.lightImpact();
                context.pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
