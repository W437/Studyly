import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import '../theme/spacing.dart';

class AvatarBadge extends StatelessWidget {
  const AvatarBadge({
    super.key,
    required this.initials,
    this.size = 48,
    this.statusColor = StudyColors.success,
    this.statusLabel,
  });

  final String initials;
  final double size;
  final Color statusColor;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: size / 2,
              backgroundColor: StudyColors.primary.withValues(alpha: 0.2),
              foregroundColor: theme.colorScheme.onSurface,
              child: Text(initials, style: theme.textTheme.titleMedium),
            ),
            Positioned(
              bottom: -4,
              right: -4,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: theme.scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (statusLabel != null) ...[
          const SizedBox(width: StudySpacing.sm),
          Text(
            statusLabel!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: StudyColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
