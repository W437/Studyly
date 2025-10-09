import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/bootstrap.dart';
import '../data/data_sources/isar_study_local_data_source.dart';
import '../data/data_sources/supabase_study_remote_data_source.dart';
import '../data/repositories/local_first_study_repository.dart';
import '../models/study_content_type.dart';
import '../models/study_document.dart';
import '../models/study_plan_task.dart';
import '../models/study_set.dart';
import '../models/user_profile.dart';
import '../services/study_repository.dart';
import 'sync_settings_provider.dart';

final studyRepositoryProvider = Provider<StudyRepository>((ref) {
  final isar = ref.watch(isarProvider);
  final supabase = Supabase.instance.client;
  final syncEnabled = ref.watch(syncSettingsProvider);

  final localDataSource = IsarStudyLocalDataSource(isar);
  final remoteDataSource = SupabaseStudyRemoteDataSource(supabase);

  final repository = LocalFirstStudyRepository(
    localDataSource: localDataSource,
    remoteDataSource: remoteDataSource,
    syncEnabled: syncEnabled,
  );

  // Listen to sync setting changes and update repository
  ref.listen<bool>(syncSettingsProvider, (_, newSyncEnabled) {
    repository.setSyncEnabled(newSyncEnabled);
  });

  return repository;
});

final userProfileProvider = StreamProvider<UserProfile>((ref) async* {
  final repository = ref.watch(studyRepositoryProvider);
  await repository.fetchProfile();
  await for (final profile in repository.watchProfile()) {
    if (profile != null) {
      yield profile;
    }
  }
});

final studySetsProvider = StreamProvider<List<StudySet>>((ref) async* {
  final repository = ref.watch(studyRepositoryProvider);
  await repository.fetchStudySets();
  yield* repository.watchStudySets();
});

final studySetDetailProvider = StreamProvider.family<StudySet?, String>((
  ref,
  id,
) async* {
  final repository = ref.watch(studyRepositoryProvider);
  await repository.fetchStudySetById(id);
  yield* repository.watchStudySetById(id);
});

final studyTasksProvider = StreamProvider.family<List<StudyPlanTask>, DateTime>(
  (ref, date) async* {
    final repository = ref.watch(studyRepositoryProvider);
    await repository.fetchTasksForDate(date);
    yield* repository.watchTasksForDate(date);
  },
);

final studyDocumentsProvider =
    StreamProvider.family<List<StudyDocument>, StudyContentType>((
      ref,
      type,
    ) async* {
      final repository = ref.watch(studyRepositoryProvider);
      await repository.fetchDocumentsByType(type);
      yield* repository.watchDocumentsByType(type);
    });
