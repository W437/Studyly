import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import '../theme/spacing.dart';

class StudyProgressBar extends StatelessWidget {
  const StudyProgressBar({
    super.key,
    required this.value,
    this.label,
    this.showValue = true,
  }) : assert(value >= 0 && value <= 1, 'value must be between 0 and 1');

  final double value;
  final String? label;
  final bool showValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percentage = (value * 100).clamp(0, 100).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: StudySpacing.xs),
            child: Text(label!, style: theme.textTheme.labelLarge),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 12,
            value: value,
            backgroundColor: StudyColors.surfaceVariant,
            valueColor: const AlwaysStoppedAnimation<Color>(
              StudyColors.primary,
            ),
          ),
        ),
        if (showValue)
          Padding(
            padding: const EdgeInsets.only(top: StudySpacing.xs),
            child: Text(
              '$percentage%',
              style: theme.textTheme.labelMedium?.copyWith(
                color: StudyColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}
