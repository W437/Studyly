import 'dart:async';

import '../../models/chat_message.dart';
import '../../models/study_content_type.dart';
import '../../models/study_document.dart';
import '../../models/study_plan_task.dart';
import '../../models/study_set.dart';
import '../../models/user_profile.dart';
import '../../services/study_repository.dart';
import '../data_sources/study_local_data_source.dart';
import '../data_sources/study_remote_data_source.dart';

class LocalFirstStudyRepository implements StudyRepository {
  LocalFirstStudyRepository({
    required StudyLocalDataSource localDataSource,
    required StudyRemoteDataSource remoteDataSource,
    bool syncEnabled = true,
  })  : _local = localDataSource,
        _remote = remoteDataSource,
        _syncEnabled = syncEnabled;

  final StudyLocalDataSource _local;
  final StudyRemoteDataSource _remote;
  bool _syncEnabled;

  /// Update sync setting at runtime
  void setSyncEnabled(bool enabled) {
    _syncEnabled = enabled;
  }

  @override
  Stream<UserProfile?> watchProfile() => _local.watchProfile();

  @override
  Future<UserProfile> fetchProfile({bool forceRefresh = false}) async {
    final localProfile = await _local.loadProfile();
    if (localProfile != null && !forceRefresh) {
      _syncSilently(() async {
        try {
          final remoteProfile = await _remote.fetchProfile();
          await _local.saveProfile(remoteProfile);
        } catch (e) {
          // Ignore sync errors when not authenticated
        }
      });
      return localProfile;
    }

    try {
      final remoteProfile = await _remote.fetchProfile();
      await _local.saveProfile(remoteProfile);
      return remoteProfile;
    } catch (e) {
      // If remote fetch fails and we have local data, return it
      if (localProfile != null) {
        return localProfile;
      }
      rethrow;
    }
  }

  @override
  Stream<List<StudySet>> watchStudySets() => _local.watchStudySets();

  @override
  Future<List<StudySet>> fetchStudySets({bool forceRefresh = false}) async {
    final localSets = await _local.loadStudySets();
    if (localSets.isNotEmpty && !forceRefresh) {
      _syncSilently(() async {
        try {
          final remoteSets = await _remote.fetchStudySets();
          await _local.saveStudySets(remoteSets);
        } catch (e) {
          // Ignore sync errors when not authenticated
        }
      });
      return localSets;
    }

    try {
      final remoteSets = await _remote.fetchStudySets();
      await _local.saveStudySets(remoteSets);
      return remoteSets;
    } catch (e) {
      // If remote fetch fails and we have local data, return it
      if (localSets.isNotEmpty) {
        return localSets;
      }
      // Return empty list instead of throwing for initial state
      return [];
    }
  }

  @override
  Stream<StudySet?> watchStudySetById(String id) => _local.watchStudySet(id);

  @override
  Future<StudySet?> fetchStudySetById(
    String id, {
    bool forceRefresh = false,
  }) async {
    final local = await _local.loadStudySet(id);
    if (local != null && !forceRefresh) {
      _syncSilently(() async {
        final remote = await _remote.fetchStudySetById(id);
        if (remote != null) {
          await _local.saveStudySet(remote);
        }
      });
      return local;
    }

    final remote = await _remote.fetchStudySetById(id);
    if (remote != null) {
      await _local.saveStudySet(remote);
    }
    return remote ?? local;
  }

  @override
  Stream<List<StudyPlanTask>> watchTasksForDate(DateTime date) =>
      _local.watchTasksForDate(date);

  @override
  Future<List<StudyPlanTask>> fetchTasksForDate(
    DateTime date, {
    bool forceRefresh = false,
  }) async {
    final local = await _local.loadTasksForDate(date);
    if (local.isNotEmpty && !forceRefresh) {
      _syncSilently(() async {
        try {
          final remote = await _remote.fetchTasksForDate(date);
          await _local.saveTasksForDate(date, remote);
        } catch (e) {
          // Ignore sync errors when not authenticated
        }
      });
      return local;
    }

    try {
      final remote = await _remote.fetchTasksForDate(date);
      await _local.saveTasksForDate(date, remote);
      return remote;
    } catch (e) {
      if (local.isNotEmpty) {
        return local;
      }
      return [];
    }
  }

  @override
  Stream<List<StudyDocument>> watchDocumentsByType(StudyContentType type) =>
      _local.watchDocumentsByType(type);

  @override
  Future<List<StudyDocument>> fetchDocumentsByType(
    StudyContentType type, {
    bool forceRefresh = false,
  }) async {
    final local = await _local.loadDocumentsByType(type);
    if (local.isNotEmpty && !forceRefresh) {
      _syncSilently(() async {
        try {
          final remote = await _remote.fetchDocumentsByType(type);
          await _local.saveDocumentsByType(type, remote);
        } catch (e) {
          // Ignore sync errors when not authenticated
        }
      });
      return local;
    }

    try {
      final remote = await _remote.fetchDocumentsByType(type);
      await _local.saveDocumentsByType(type, remote);
      return remote;
    } catch (e) {
      if (local.isNotEmpty) {
        return local;
      }
      return [];
    }
  }

  @override
  Stream<List<ChatMessage>> watchChatTranscript() =>
      _local.watchChatTranscript();

  @override
  Future<List<ChatMessage>> loadInitialChatTranscript({
    bool forceRefresh = false,
  }) async {
    final local = await _local.loadChatTranscript();
    if (local.isNotEmpty && !forceRefresh) {
      _syncSilently(() async {
        try {
          final remote = await _remote.loadInitialChatTranscript();
          await _local.replaceChatTranscript(remote);
        } catch (e) {
          // Ignore sync errors when not authenticated
        }
      });
      return local;
    }

    try {
      final remote = await _remote.loadInitialChatTranscript();
      await _local.replaceChatTranscript(remote);
      return remote;
    } catch (e) {
      if (local.isNotEmpty) {
        return local;
      }
      return [];
    }
  }

  @override
  Future<void> replaceChatTranscript(List<ChatMessage> messages) async {
    await _local.replaceChatTranscript(messages);
  }

  @override
  Future<void> appendChatMessage(ChatMessage message) async {
    await _local.appendChatMessage(message);
  }

  @override
  Future<void> updateChatMessage(ChatMessage message) async {
    await _local.updateChatMessage(message);
    // TODO: Optionally sync feedback to remote
  }

  @override
  Future<ChatMessage> generateBotReply(String prompt, {String? imageUrl}) async {
    final reply = await _remote.generateBotReply(prompt, imageUrl: imageUrl);
    await _local.appendChatMessage(reply);
    return reply;
  }

  void _syncSilently(Future<void> Function() action) {
    if (!_syncEnabled) {
      return; // Don't sync if sync is disabled
    }
    unawaited(
      action().catchError((Object error, StackTrace stackTrace) {
        // TODO: route to logger once logging infrastructure is in place.
      }),
    );
  }
}
