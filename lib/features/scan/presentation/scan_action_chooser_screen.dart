import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/routes.dart';
import '../../../core/models/generation_result.dart';
import '../../../core/providers/scan_providers.dart';

class ScanActionChooserScreen extends ConsumerWidget {
  const ScanActionChooserScreen({
    required this.scannedItemId,
    super.key,
  });

  final String scannedItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanState = ref.watch(scanControllerProvider);
    final currentItem = scanState.currentItem;

    if (scanState.isLoading || currentItem == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Choose Action'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Action'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'What would you like to do?',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose an action to process your scanned content',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 24),

            // Preview Card (collapsible)
            _PreviewCard(
              imagePath: currentItem.localImagePath,
              text: currentItem.ocrText ?? '',
            ),
            const SizedBox(height: 24),

            // Action Cards Grid (2x2)
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.9,
              children: [
                _ActionCard(
                  icon: Icons.chat_bubble_outline,
                  title: 'Solve in Chat',
                  description: 'Get AI help with this question',
                  color: Colors.blue,
                  onTap: () {
                    ref
                        .read(scanControllerProvider.notifier)
                        .selectAction(scannedItemId, 'solve_chat');
                    // TODO: Navigate to chat screen with scanned content
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Chat feature coming soon!'),
                      ),
                    );
                  },
                ),
                _ActionCard(
                  icon: Icons.style_outlined,
                  title: 'Flashcards',
                  description: 'Create study cards from this',
                  color: Colors.purple,
                  onTap: () {
                    ref
                        .read(scanControllerProvider.notifier)
                        .selectAction(scannedItemId, 'flashcards');
                    context.push(
                      AppRoute.scanGenerationReview.path
                          .replaceAll(':id', scannedItemId)
                          .replaceAll(':type', GenerationType.flashcards.name),
                    );
                  },
                ),
                _ActionCard(
                  icon: Icons.description_outlined,
                  title: 'Explanation',
                  description: 'Generate detailed notes',
                  color: Colors.green,
                  onTap: () {
                    ref
                        .read(scanControllerProvider.notifier)
                        .selectAction(scannedItemId, 'explanation');
                    context.push(
                      AppRoute.scanGenerationReview.path
                          .replaceAll(':id', scannedItemId)
                          .replaceAll(':type', GenerationType.explanation.name),
                    );
                  },
                ),
                _ActionCard(
                  icon: Icons.quiz_outlined,
                  title: 'Practice',
                  description: 'Create practice questions',
                  color: Colors.orange,
                  onTap: () {
                    ref
                        .read(scanControllerProvider.notifier)
                        .selectAction(scannedItemId, 'exercise');
                    context.push(
                      AppRoute.scanGenerationReview.path
                          .replaceAll(':id', scannedItemId)
                          .replaceAll(':type', GenerationType.exercise.name),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatefulWidget {
  const _PreviewCard({
    required this.imagePath,
    required this.text,
  });

  final String imagePath;
  final String text;

  @override
  State<_PreviewCard> createState() => _PreviewCardState();
}

class _PreviewCardState extends State<_PreviewCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Image thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(widget.imagePath),
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Text preview
                  Expanded(
                    child: Text(
                      widget.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
              child: Text(
                widget.text,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 36,
                color: color,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[700],
                  ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
