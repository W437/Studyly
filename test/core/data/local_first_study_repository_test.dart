import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:studyly/core/data/data_sources/in_memory_study_local_data_source.dart';
import 'package:studyly/core/data/data_sources/study_remote_data_source.dart';
import 'package:studyly/core/data/repositories/local_first_study_repository.dart';
import 'package:studyly/core/models/chat_message.dart';
import 'package:studyly/core/models/study_content_type.dart';
import 'package:studyly/core/models/study_document.dart';
import 'package:studyly/core/models/study_plan_task.dart';
import 'package:studyly/core/models/study_set.dart';
import 'package:studyly/core/models/user_profile.dart';

class _FakeRemoteDataSource implements StudyRemoteDataSource {
  _FakeRemoteDataSource({required this.profile, required this.studySets});

  UserProfile profile;
  List<StudySet> studySets;
  int profileFetchCount = 0;
  int studySetsFetchCount = 0;

  @override
  Future<UserProfile> fetchProfile() async {
    profileFetchCount++;
    return profile;
  }

  @override
  Future<List<StudySet>> fetchStudySets() async {
    studySetsFetchCount++;
    return studySets;
  }

  @override
  Future<StudySet?> fetchStudySetById(String id) =>
      throw UnimplementedError();

  @override
  Future<List<StudyPlanTask>> fetchTasksForDate(DateTime date) =>
      throw UnimplementedError();

  @override
  Future<List<StudyDocument>> fetchDocumentsByType(StudyContentType type) =>
      throw UnimplementedError();

  @override
  Future<List<ChatMessage>> loadInitialChatTranscript() =>
      throw UnimplementedError();

  @override
  Future<ChatMessage> generateBotReply(String prompt) =>
      throw UnimplementedError();
}

void main() {
  group('LocalFirstStudyRepository', () {
    late InMemoryStudyLocalDataSource local;
    late _FakeRemoteDataSource remote;
    late LocalFirstStudyRepository repository;

    setUp(() {
      local = InMemoryStudyLocalDataSource();
      remote = _FakeRemoteDataSource(
        profile: const UserProfile(
          id: 'user-1',
          displayName: 'Initial',
          email: 'initial@example.com',
          avatarUrl: 'https://example.com/avatar.png',
          activePlan: 'Free',
          focusAreas: [StudyMaterialTag.biology],
        ),
        studySets: const [
          StudySet(
            id: 'set-1',
            title: 'Biology Basics',
            flashcards: 12,
            explanations: 8,
            exercises: 5,
            views: '120',
            borderColor: 0xFF42A5F5,
            tag: StudyMaterialTag.biology,
            description: 'Entry level study set.',
          ),
        ],
      );
      repository = LocalFirstStudyRepository(
        localDataSource: local,
        remoteDataSource: remote,
      );
    });

    test('seeds profile locally and syncs remote updates in background', () async {
      final first = await repository.fetchProfile();

      expect(first.displayName, 'Initial');
      expect(remote.profileFetchCount, 1);

      remote.profile = first.copyWith(displayName: 'Updated');

      final second = await repository.fetchProfile();

      expect(second.displayName, 'Initial');
      expect(remote.profileFetchCount, 2);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      final cached = await local.loadProfile();
      expect(cached?.displayName, 'Updated');
    });

    test('exposes cached study sets after first fetch', () async {
      await repository.fetchStudySets();

      final cachedSets = await local.loadStudySets();
      expect(cachedSets, isNotEmpty);
      expect(remote.studySetsFetchCount, 1);

      final stream = repository.watchStudySets();
      expect(
        await stream.first,
        equals(cachedSets),
      );
    });
  });
}
