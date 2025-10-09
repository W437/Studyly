import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/theme/study_theme.dart';
import 'navigation/app_router.dart';

class StudylyApp extends ConsumerWidget {
  const StudylyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: buildStudyTheme(),
      routerConfig: router,
    );
  }
}
