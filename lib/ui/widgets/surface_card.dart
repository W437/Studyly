import 'package:flutter/material.dart';

import '../theme/study_theme.dart';

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.header,
    this.footer,
  });

  final Widget child;
  final Widget? header;
  final Widget? footer;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<StudyBrandTheme>();

    final card = Card(
      margin: margin,
      child: Padding(
        padding: padding ?? brand?.cardPadding ?? const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (header != null) ...[header!, const SizedBox(height: 16)],
            child,
            if (footer != null) ...[const SizedBox(height: 16), footer!],
          ],
        ),
      ),
    );

    if (brand == null) {
      return card;
    }

    return DecoratedBox(
      decoration: BoxDecoration(gradient: brand.primaryGradient),
      child: ClipRRect(borderRadius: brand.surfaceRadius, child: card),
    );
  }
}
