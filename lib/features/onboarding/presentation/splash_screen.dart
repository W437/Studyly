import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/navigation/routes.dart';
import '../../../ui/theme/color_tokens.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToOnboarding();
  }

  void _navigateToOnboarding() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        // TODO: Temporarily disabled onboarding - change back to AppRoute.onboarding.path when ready
        context.go(AppRoute.home.path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Studyly Logo
            ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Image.asset(
                'assets/logos/studyly_icon.png',
                width: 120,
                height: 120,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Studyly',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: StudyColors.primary,
              ),
            ),
            const SizedBox(height: 100),
            // Loading Circle
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                valueColor: AlwaysStoppedAnimation<Color>(StudyColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
