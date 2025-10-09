import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for managing sync settings
final syncSettingsProvider = StateNotifierProvider<SyncSettingsNotifier, bool>((ref) {
  return SyncSettingsNotifier();
});

class SyncSettingsNotifier extends StateNotifier<bool> {
  SyncSettingsNotifier() : super(true) {
    _loadSettings();
  }

  static const String _syncEnabledKey = 'sync_enabled';

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_syncEnabledKey) ?? true; // Default: sync enabled
  }

  Future<void> setSyncEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_syncEnabledKey, enabled);
  }

  Future<void> toggleSync() async {
    await setSyncEnabled(!state);
  }
}
