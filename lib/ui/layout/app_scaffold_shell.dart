import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/navigation/routes.dart';
import '../responsive/breakpoints.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/avatar_badge.dart';
import '../widgets/tag_pill.dart';
import 'app_navigation.dart';
import 'app_top_bar.dart';

class AppScaffoldShell extends ConsumerWidget {
  const AppScaffoldShell({super.key, required this.state, required this.child});

  final GoRouterState state;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navItems = _navigationItems;
    final currentRoute = _resolveRoute(state.matchedLocation, navItems);
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < Breakpoints.medium;

    void onDestinationTap(AppRoute route) {
      if (route == currentRoute) {
        return;
      }
      context.go(route.path);
    }

    return AppScaffold(
      title: _titleForRoute(currentRoute),
      showSearch: currentRoute == AppRoute.library,
      topBar: null,
      bottomBar: isCompact
          ? AppNavigationBar(
              items: navItems,
              currentRoute: currentRoute,
              onSelected: onDestinationTap,
            )
          : null,
      sideNavigation: isCompact
          ? null
          : AppNavigationBar(
              items: navItems,
              currentRoute: currentRoute,
              onSelected: onDestinationTap,
              useRail: true,
            ),
      child: child,
    );
  }

  static AppRoute _resolveRoute(
    String location,
    List<AppNavigationItem> items,
  ) {
    for (final item in items) {
      final path = item.route.path;
      if (path == '/') {
        if (location == '/') {
          return item.route;
        }
        continue;
      }
      if (location.startsWith(path)) {
        return item.route;
      }
    }
    return items.first.route;
  }

  static String _titleForRoute(AppRoute route) {
    return switch (route) {
      AppRoute.home => 'Home',
      AppRoute.library => 'Library',
      AppRoute.account => 'Account',
      AppRoute.chat => 'Chat',
      AppRoute.studySetDetail => 'Study Set',
      AppRoute.studySetCreate => 'Create Study Set',
      AppRoute.flashcardReview => 'Review Flashcards',
      AppRoute.flashcardCreate => 'Add Flashcards',
      AppRoute.splash => 'Splash',
      AppRoute.onboarding => 'Onboarding',
      AppRoute.authWelcome => 'Auth',
      AppRoute.questionnaire => 'Questionnaire',
      AppRoute.scanPreview => 'Scan Preview',
      AppRoute.scanOcr => 'Scan OCR',
      AppRoute.scanActionChooser => 'Choose Action',
      AppRoute.scanGenerationReview => 'Review Content',
    };
  }

  static List<AppNavigationItem> get _navigationItems => const [
    AppNavigationItem(
      route: AppRoute.home,
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
    ),
    AppNavigationItem(
      route: AppRoute.chat,
      icon: Icons.chat_bubble_outline,
      activeIcon: Icons.chat_bubble,
      label: 'Chat',
    ),
    AppNavigationItem(
      route: AppRoute.library,
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view,
      label: 'Library',
    ),
    AppNavigationItem(
      route: AppRoute.account,
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Account',
    ),
  ];
}
