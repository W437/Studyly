import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import '../theme/spacing.dart';

abstract class BaseButton extends StatelessWidget {
  const BaseButton({
    super.key,
    required this.label,
    this.onPressed,
    this.leading,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? leading;

  ButtonStyle resolveStyle(BuildContext context);

  @override
  Widget build(BuildContext context) {
    final style = resolveStyle(context);

    if (leading != null) {
      return _buildWithIcon(style);
    }

    return _buildDefault(style);
  }

  Widget _buildDefault(ButtonStyle style);

  Widget _buildWithIcon(ButtonStyle style);
}

class PrimaryButton extends BaseButton {
  const PrimaryButton({
    super.key,
    required super.label,
    super.onPressed,
    super.leading,
  });

  @override
  ButtonStyle resolveStyle(BuildContext context) {
    return FilledButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      padding: const EdgeInsets.symmetric(
        horizontal: StudySpacing.lg,
        vertical: StudySpacing.md,
      ),
      elevation: 0,
      shadowColor: Colors.transparent,
      overlayColor: Colors.white.withOpacity(0.1),
      splashFactory: NoSplash.splashFactory,
    );
  }

  @override
  Widget _buildDefault(ButtonStyle style) {
    return FilledButton(style: style, onPressed: onPressed, child: Text(label));
  }

  @override
  Widget _buildWithIcon(ButtonStyle style) {
    return FilledButton.icon(
      style: style,
      onPressed: onPressed,
      label: Text(label),
      icon: leading!,
    );
  }
}

class SecondaryButton extends BaseButton {
  const SecondaryButton({
    super.key,
    required super.label,
    super.onPressed,
    super.leading,
  });

  @override
  ButtonStyle resolveStyle(BuildContext context) {
    return OutlinedButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      side: const BorderSide(color: StudyColors.divider),
      padding: const EdgeInsets.symmetric(
        horizontal: StudySpacing.lg,
        vertical: StudySpacing.md,
      ),
      elevation: 0,
      shadowColor: Colors.transparent,
      overlayColor: Colors.black.withOpacity(0.05),
      splashFactory: NoSplash.splashFactory,
    );
  }

  @override
  Widget _buildDefault(ButtonStyle style) {
    return OutlinedButton(
      style: style,
      onPressed: onPressed,
      child: Text(label),
    );
  }

  @override
  Widget _buildWithIcon(ButtonStyle style) {
    return OutlinedButton.icon(
      style: style,
      onPressed: onPressed,
      label: Text(label),
      icon: leading!,
    );
  }
}

class TextGhostButton extends BaseButton {
  const TextGhostButton({
    super.key,
    required super.label,
    super.onPressed,
    super.leading,
  });

  @override
  ButtonStyle resolveStyle(BuildContext context) {
    return TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.secondary,
      padding: const EdgeInsets.symmetric(horizontal: StudySpacing.md),
      elevation: 0,
      shadowColor: Colors.transparent,
      overlayColor: Colors.black.withOpacity(0.05),
      splashFactory: NoSplash.splashFactory,
    );
  }

  @override
  Widget _buildDefault(ButtonStyle style) {
    return TextButton(style: style, onPressed: onPressed, child: Text(label));
  }

  @override
  Widget _buildWithIcon(ButtonStyle style) {
    return TextButton.icon(
      style: style,
      onPressed: onPressed,
      label: Text(label),
      icon: leading!,
    );
  }
}
