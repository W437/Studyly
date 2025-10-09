import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/study_content_type.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/providers/sync_settings_provider.dart';
import '../../../ui/widgets/profile_picture_widget.dart';
import 'profile_picture_editor_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const routeName = 'settings';
  static const routePath = '/settings';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);
    final syncEnabled = ref.watch(syncSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('Error loading settings: $error'),
        ),
        data: (profile) => Theme(
          data: Theme.of(context).copyWith(
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
          ),
          child: ListView(
            children: [
            // Profile Section
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'PROFILE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ),
            ListTile(
              leading: ProfilePictureWidget(
                profilePicture: profile.profilePicture,
                size: 48,
              ),
              title: Text(profile.displayName),
              subtitle: Text(profile.email),
              trailing: TextButton(
                onPressed: () async {
                  final result = await Navigator.push<Map<String, String>>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfilePictureEditorScreen(
                        initialColor: profile.profileBgColor,
                        initialEmoji: profile.profileEmoji,
                      ),
                    ),
                  );

                  if (result != null) {
                    // Update profile in database
                    final userId = Supabase.instance.client.auth.currentUser?.id;
                    if (userId != null) {
                      await Supabase.instance.client
                          .from('user_profiles')
                          .update({
                        'profile_bg_color': result['color'],
                        'profile_emoji': result['emoji'],
                      })
                          .eq('user_id', userId);

                      // Refresh profile
                      ref.invalidate(userProfileProvider);

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Profile picture updated!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  }
                },
                child: const Text('Edit'),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.card_membership),
              title: const Text('Plan'),
              subtitle: Text(profile.activePlan),
            ),

            const Divider(),

            // Sync Settings Section
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'SYNC & STORAGE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.cloud_sync),
              title: const Text('Cloud Sync'),
              subtitle: Text(
                syncEnabled
                  ? 'Data syncs to cloud automatically'
                  : 'Data stays on device only',
              ),
              value: syncEnabled,
              onChanged: (value) {
                ref.read(syncSettingsProvider.notifier).setSyncEnabled(value);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      value
                        ? 'Cloud sync enabled. Your data will sync automatically.'
                        : 'Cloud sync disabled. Data will remain local only.',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            if (!syncEnabled)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 72.0, vertical: 8.0),
                child: Text(
                  'When sync is off, your study data stays on this device and won\'t be backed up to the cloud.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange,
                  ),
                ),
              ),

            const Divider(),

            // Focus Areas Section
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'FOCUS AREAS',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.category),
              title: const Text('Study Topics'),
              subtitle: Text(
                profile.focusAreas.map((tag) {
                  switch (tag) {
                    case StudyMaterialTag.biology:
                      return 'Biology';
                    case StudyMaterialTag.computerScience:
                      return 'Computer Science';
                    case StudyMaterialTag.engineering:
                      return 'Engineering';
                    case StudyMaterialTag.business:
                      return 'Business';
                    case StudyMaterialTag.mathematics:
                      return 'Mathematics';
                    case StudyMaterialTag.physics:
                      return 'Physics';
                    case StudyMaterialTag.socialScience:
                      return 'Social Science';
                    case StudyMaterialTag.language:
                      return 'Language';
                  }
                }).join(', '),
              ),
            ),

            const Divider(),

            // About Section
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'ABOUT',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ),
            const ListTile(
              leading: Icon(Icons.info),
              title: Text('Version'),
              subtitle: Text('1.0.0'),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
