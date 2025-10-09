import 'package:flutter/material.dart';

@immutable
final class StudyColors {
  const StudyColors._();

  static const Color primary = Color(0xFF4DB6AC);
  static const Color primaryDark = Color(0xFF26A69A);
  static const Color accent = Color(0xFFFFB74D);
  static const Color background = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF5F5F5);
  static const Color textPrimary = Color(0xFF263238);
  static const Color textSecondary = Color(0xFF607D8B);
  static const Color textTertiary = Color(0xFF90A4AE);
  static const Color success = Color(0xFF66BB6A);
  static const Color warning = Color(0xFFFFB74D);
  static const Color error = Color(0xFFEF5350);
  static const Color divider = Color(0xFFE0E0E0);

  static const Color progressGreen = Color(0xFF4CAF50);
  static const Color progressOrange = Color(0xFFFF9800);
  static const Color borderAccent = Color(0xFFE64A19);
}

@immutable
class StudyGradients {
  const StudyGradients._();

  static const LinearGradient primaryGlow = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4DB6AC), Color(0xFF80CBC4)],
  );
}
