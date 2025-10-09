import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/study_content_type.dart';
import '../models/study_document.dart';
import '../models/study_plan_task.dart';
import '../models/study_set.dart';
import '../models/user_profile.dart';
import '../services/mock_study_repository.dart';
import '../services/study_repository.dart';

final studyRepositoryProvider = Provider<StudyRepository>((ref) {
  return MockStudyRepository();
});

final userProfileProvider = FutureProvider<UserProfile>((ref) async {
  final repository = ref.watch(studyRepositoryProvider);
  return repository.fetchProfile();
});

final studySetsProvider = FutureProvider<List<StudySet>>((ref) async {
  final repository = ref.watch(studyRepositoryProvider);
  return repository.fetchStudySets();
});

final studySetDetailProvider = FutureProvider.family<StudySet?, String>((
  ref,
  id,
) async {
  final repository = ref.watch(studyRepositoryProvider);
  return repository.fetchStudySetById(id);
});

final studyTasksProvider = FutureProvider.family<List<StudyPlanTask>, DateTime>(
  (ref, date) async {
    final repository = ref.watch(studyRepositoryProvider);
    return repository.fetchTasksForDate(date);
  },
);

final studyDocumentsProvider =
    FutureProvider.family<List<StudyDocument>, StudyContentType>((
      ref,
      type,
    ) async {
      final repository = ref.watch(studyRepositoryProvider);
      return repository.fetchDocumentsByType(type);
    });
