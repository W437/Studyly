import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';

class SharedHeader extends StatelessWidget {
  const SharedHeader({
    super.key,
    required this.title,
    this.showSearch = false,
    this.showBackButton = false,
    this.customAction,
  });

  final String title;
  final bool showSearch;
  final bool showBackButton;
  final Widget? customAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          if (showBackButton)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black87),
              onPressed: () => Navigator.pop(context),
            )
          else
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: StudyColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.school,
                color: StudyColors.primary,
                size: 24,
              ),
            ),
          const Spacer(),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: StudyColors.textPrimary,
            ),
          ),
          const Spacer(),
          customAction ??
              IconButton(
                onPressed: () {},
                icon: Icon(showSearch ? Icons.search : Icons.more_vert),
                color: StudyColors.textSecondary,
                iconSize: 28,
              ),
        ],
      ),
    );
  }
}
