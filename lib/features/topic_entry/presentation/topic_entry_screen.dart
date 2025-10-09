import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/routes.dart';
import '../../../core/models/study_content_type.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/providers/sync_settings_provider.dart';
import '../../../ui/theme/color_tokens.dart';
import '../../../ui/theme/spacing.dart';
import '../../settings/presentation/settings_screen.dart';

class TopicEntryScreen extends ConsumerWidget {
  const TopicEntryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);

    return profileAsync.when(
      data: _ProfileLoadedView.new,
      loading: () => const _ProfileEmptyView(),
      error: (error, stack) => const _ProfileEmptyView(),
    );
  }
}

class _ProfileLoadedView extends StatelessWidget {
  const _ProfileLoadedView(UserProfile profile) : _profile = profile;

  final UserProfile _profile;

  String get _initials {
    final name = _profile.displayName.trim();
    if (name.isEmpty) {
      return 'U';
    }
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.last.isNotEmpty ? parts.last[0] : '';
    final combined = (first + last).trim();
    return combined.isEmpty ? 'U' : combined.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final syncEnabled = ref.watch(syncSettingsProvider);
        final theme = Theme.of(context);

        return ListView(
          padding: const EdgeInsets.all(StudySpacing.lg),
          children: [
        Container(
          padding: const EdgeInsets.all(StudySpacing.lg),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4DB6AC), Color(0xFF80CBC4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('👑', style: TextStyle(fontSize: 28)),
                ),
              ),
              const SizedBox(width: StudySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upgrade Plan Now!',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You are on the ${_profile.activePlan} plan. Unlock more smart study features.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: StudySpacing.lg),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(StudySpacing.md),
            leading: CircleAvatar(
              radius: 30,
              backgroundColor: StudyColors.surfaceVariant,
              child: Text(
                _initials,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: StudyColors.primary,
                ),
              ),
            ),
            title: Text(
              _profile.displayName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: StudyColors.textPrimary,
              ),
            ),
            subtitle: Text(
              '${_profile.email}\nFocus areas: ${_profile.focusAreas.map((tag) => tag.label).join(', ')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: StudyColors.textSecondary,
                height: 1.4,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: StudyColors.textTertiary,
            ),
            onTap: () {},
          ),
        ),
        const SizedBox(height: StudySpacing.lg),
        // Sync Settings Card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  StudySpacing.lg,
                  StudySpacing.md,
                  StudySpacing.lg,
                  StudySpacing.xs,
                ),
                child: Text(
                  'SYNC & STORAGE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: StudyColors.textTertiary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: StudySpacing.lg,
                  vertical: StudySpacing.xs,
                ),
                secondary: Icon(
                  syncEnabled ? Icons.cloud_sync : Icons.cloud_off,
                  color: syncEnabled ? StudyColors.primary : StudyColors.textSecondary,
                  size: 24,
                ),
                title: Text(
                  'Cloud Sync',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: StudyColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  syncEnabled
                      ? 'Data syncs to cloud automatically'
                      : 'Data stays on device only',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: StudyColors.textSecondary,
                  ),
                ),
                value: syncEnabled,
                activeColor: StudyColors.primary,
                onChanged: (value) {
                  ref.read(syncSettingsProvider.notifier).setSyncEnabled(value);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        value
                            ? '☁️ Cloud sync enabled. Your data will sync automatically.'
                            : '📱 Cloud sync disabled. Data will remain local only.',
                      ),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              if (!syncEnabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    72.0,
                    0,
                    StudySpacing.lg,
                    StudySpacing.md,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your data won\'t be backed up to cloud',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: StudySpacing.lg),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              _SettingsItem(
                icon: Icons.history,
                title: 'Scan History',
                onTap: () {},
              ),
              const Divider(height: 1, indent: 60),
              _SettingsItem(
                icon: Icons.settings_outlined,
                title: 'Advanced Settings',
                onTap: () => context.pushNamed(SettingsScreen.routeName),
              ),
            ],
          ),
        ),
        const SizedBox(height: StudySpacing.lg),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              _SettingsItem(
                icon: Icons.shield_outlined,
                title: 'Account & Security',
                onTap: () {},
              ),
              const Divider(height: 1, indent: 60),
              _SettingsItem(
                icon: Icons.credit_card_outlined,
                title: 'Payment Methods',
                onTap: () {},
              ),
              const Divider(height: 1, indent: 60),
              _SettingsItem(
                icon: Icons.receipt_long_outlined,
                title: 'Billing & Subscriptions',
                onTap: () {},
              ),
              const Divider(height: 1, indent: 60),
              _SettingsItem(
                icon: Icons.swap_horiz,
                title: 'Linked Accounts',
                onTap: () {},
              ),
              const Divider(height: 1, indent: 60),
              _SettingsItem(
                icon: Icons.visibility_outlined,
                title: 'App Appearance',
                onTap: () {},
              ),
              const Divider(height: 1, indent: 60),
              _SettingsItem(
                icon: Icons.help_outline,
                title: 'Help & Support',
                onTap: () {},
              ),
              const Divider(height: 1, indent: 60),
              _SettingsItem(icon: Icons.logout, title: 'Log out', onTap: () {}),
            ],
          ),
        ),
            const SizedBox(height: 100),
          ],
        );
      },
    );
  }
}

class _ProfileEmptyView extends StatelessWidget {
  const _ProfileEmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(StudySpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_outline,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 24),
            Text(
              'No Profile Found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Please sign in to view your profile\nand personalized content',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                context.go(AppRoute.authWelcome.path);
              },
              icon: const Icon(Icons.login),
              label: const Text('Sign In'),
              style: ElevatedButton.styleFrom(
                backgroundColor: StudyColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: StudySpacing.lg,
        vertical: StudySpacing.xs,
      ),
      leading: Icon(icon, color: StudyColors.textPrimary, size: 24),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: StudyColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: StudyColors.textTertiary,
      ),
      onTap: onTap,
    );
  }
}
