import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/generation_result.dart';
import '../../features/analytics/presentation/analytics_screen.dart';
import '../../features/auth/presentation/auth_welcome_screen.dart';
import '../../features/chat/presentation/chat_screen_wrapper.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/questionnaire/presentation/questionnaire_flow_screen.dart';
import '../../features/scan/presentation/generation_review_screen.dart';
import '../../features/scan/presentation/scan_action_chooser_screen.dart';
import '../../features/scan/presentation/scan_ocr_screen.dart';
import '../../features/scan/presentation/scan_preview_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/study_session/presentation/study_session_screen.dart';
import '../../features/study_set/presentation/study_set_detail_screen.dart';
import '../../features/topic_entry/presentation/topic_entry_screen.dart';
import '../../ui/layout/app_scaffold_shell.dart';
import 'routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoute.splash.path,
    routes: [
      // Standalone routes (no app scaffold)
      GoRoute(
        path: AppRoute.splash.path,
        name: AppRoute.splash.name,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoute.onboarding.path,
        name: AppRoute.onboarding.name,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoute.authWelcome.path,
        name: AppRoute.authWelcome.name,
        builder: (context, state) => const AuthWelcomeScreen(),
      ),
      GoRoute(
        path: AppRoute.questionnaire.path,
        name: AppRoute.questionnaire.name,
        builder: (context, state) => const QuestionnaireFlowScreen(),
      ),
      GoRoute(
        path: AppRoute.chat.path,
        name: AppRoute.chat.name,
        builder: (context, state) => const ChatScreenWrapper(),
      ),
      GoRoute(
        path: AppRoute.studySetDetail.path,
        name: AppRoute.studySetDetail.name,
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? 'study-set';
          return StudySetDetailScreen(id: id);
        },
      ),
      GoRoute(
        path: SettingsScreen.routePath,
        name: SettingsScreen.routeName,
        builder: (context, state) => const SettingsScreen(),
      ),
      // Scan feature routes
      GoRoute(
        path: AppRoute.scanPreview.path,
        name: AppRoute.scanPreview.name,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ScanPreviewScreen(scannedItemId: id);
        },
      ),
      GoRoute(
        path: AppRoute.scanOcr.path,
        name: AppRoute.scanOcr.name,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ScanOcrScreen(scannedItemId: id);
        },
      ),
      GoRoute(
        path: AppRoute.scanActionChooser.path,
        name: AppRoute.scanActionChooser.name,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ScanActionChooserScreen(scannedItemId: id);
        },
      ),
      GoRoute(
        path: AppRoute.scanGenerationReview.path,
        name: AppRoute.scanGenerationReview.name,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final typeStr = state.pathParameters['type']!;
          final type = GenerationType.values.firstWhere(
            (e) => e.name == typeStr,
          );
          return GenerationReviewScreen(
            scannedItemId: id,
            type: type,
          );
        },
      ),
      // Main app routes (with app scaffold)
      ShellRoute(
        builder: (context, state, child) =>
            AppScaffoldShell(state: state, child: child),
        routes: [
          GoRoute(
            path: AppRoute.home.path,
            name: AppRoute.home.name,
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: const DashboardScreen(),
            ),
          ),
          GoRoute(
            path: AppRoute.explore.path,
            name: AppRoute.explore.name,
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: const StudySessionScreen(),
            ),
          ),
          GoRoute(
            path: AppRoute.library.path,
            name: AppRoute.library.name,
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: const AnalyticsScreen(),
            ),
          ),
          GoRoute(
            path: AppRoute.account.path,
            name: AppRoute.account.name,
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: const TopicEntryScreen(),
            ),
          ),
        ],
      ),
    ],
    debugLogDiagnostics: true,
  );
});
