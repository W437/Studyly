import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import '../theme/spacing.dart';
import '../theme/study_theme.dart';
import 'shared_header.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.child,
    this.title,
    this.showSearch = false,
    this.topBar,
    this.bottomBar,
    this.sideNavigation,
    this.maxContentWidth = 980,
    this.padding,
  });

  final Widget child;
  final String? title;
  final bool showSearch;
  final Widget? topBar;
  final Widget? bottomBar;
  final Widget? sideNavigation;
  final double maxContentWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: StudyColors.background,
      body: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sideNavigation != null) sideNavigation!,
            Expanded(
              child: Column(
                children: [
                  if (title != null)
                    SharedHeader(title: title!, showSearch: showSearch),
                  if (topBar != null) topBar!,
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: bottomBar,
    );
  }
}
