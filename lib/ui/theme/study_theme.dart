import 'package:flutter/material.dart';

import 'color_tokens.dart';
import 'spacing.dart';
import 'text_tokens.dart';

@immutable
class StudyBrandTheme extends ThemeExtension<StudyBrandTheme> {
  const StudyBrandTheme({
    required this.surfaceRadius,
    required this.primaryGradient,
    required this.cardPadding,
  });

  final BorderRadius surfaceRadius;
  final LinearGradient primaryGradient;
  final EdgeInsets cardPadding;

  @override
  StudyBrandTheme copyWith({
    BorderRadius? surfaceRadius,
    LinearGradient? primaryGradient,
    EdgeInsets? cardPadding,
  }) {
    return StudyBrandTheme(
      surfaceRadius: surfaceRadius ?? this.surfaceRadius,
      primaryGradient: primaryGradient ?? this.primaryGradient,
      cardPadding: cardPadding ?? this.cardPadding,
    );
  }

  @override
  StudyBrandTheme lerp(ThemeExtension<StudyBrandTheme>? other, double t) {
    if (other is! StudyBrandTheme) {
      return this;
    }

    return StudyBrandTheme(
      surfaceRadius:
          BorderRadius.lerp(surfaceRadius, other.surfaceRadius, t) ??
          surfaceRadius,
      primaryGradient:
          LinearGradient.lerp(primaryGradient, other.primaryGradient, t) ??
          primaryGradient,
      cardPadding:
          EdgeInsets.lerp(cardPadding, other.cardPadding, t) ?? cardPadding,
    );
  }
}

ThemeData buildStudyTheme() {
  final base = ThemeData.light(useMaterial3: true);
  final textTheme = StudyTypography.textTheme(
    base.textTheme.apply(
      bodyColor: StudyColors.textPrimary,
      displayColor: StudyColors.textPrimary,
    ),
  );

  final colorScheme = ColorScheme.fromSeed(
    seedColor: StudyColors.primary,
    brightness: Brightness.light,
    primary: StudyColors.primary,
    secondary: StudyColors.accent,
    tertiary: StudyColors.success,
    surface: StudyColors.surface,
    error: StudyColors.error,
  );

  return base.copyWith(
    colorScheme: colorScheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: StudyColors.background,
    canvasColor: StudyColors.background,
    appBarTheme: AppBarTheme(
      backgroundColor: StudyColors.background,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: StudyColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      margin: const EdgeInsets.all(0),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: StudyColors.primary,
        foregroundColor: StudyColors.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: textTheme.labelLarge,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: StudyColors.accent,
        foregroundColor: StudyColors.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: StudyColors.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: StudyColors.divider),
        textStyle: textTheme.labelMedium,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: StudyColors.surfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: StudyColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: StudyColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: StudyColors.primary, width: 2),
      ),
      hintStyle: textTheme.bodyMedium?.copyWith(
        color: StudyColors.textSecondary,
      ),
      labelStyle: textTheme.bodyMedium?.copyWith(
        color: StudyColors.textSecondary,
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      unselectedIconTheme: IconThemeData(color: StudyColors.textSecondary),
      selectedIconTheme: IconThemeData(color: StudyColors.primary),
      selectedLabelTextStyle: textTheme.labelLarge?.copyWith(
        color: StudyColors.textPrimary,
      ),
      unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        color: StudyColors.textSecondary,
      ),
      indicatorColor: StudyColors.primary.withValues(alpha: 0.12),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: StudyColors.surface,
      selectedItemColor: StudyColors.primary,
      unselectedItemColor: StudyColors.textSecondary,
      selectedLabelStyle: textTheme.labelMedium,
      unselectedLabelStyle: textTheme.labelSmall,
      type: BottomNavigationBarType.fixed,
    ),
    dividerTheme: const DividerThemeData(
      color: StudyColors.divider,
      thickness: 1,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: StudyColors.surfaceVariant,
      labelStyle: textTheme.labelMedium,
      side: const BorderSide(color: StudyColors.divider),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    extensions: const [
      StudyBrandTheme(
        surfaceRadius: BorderRadius.all(Radius.circular(24)),
        primaryGradient: StudyGradients.primaryGlow,
        cardPadding: EdgeInsets.symmetric(
          horizontal: StudySpacing.lg,
          vertical: StudySpacing.md,
        ),
      ),
    ],
  );
}
