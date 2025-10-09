import 'dart:async';

import 'package:isar/isar.dart';

import '../../models/chat_message.dart';
import '../../models/exercise.dart';
import '../../models/explanation_doc.dart';
import '../../models/flashcard.dart';
import '../../models/generation_result.dart';
import '../../models/scanned_item.dart';
import '../../models/study_content_type.dart';
import '../../models/study_document.dart';
import '../../models/study_plan_task.dart';
import '../../models/study_set.dart';
import '../../models/user_profile.dart';
import '../models/chat_message_entity.dart';
import '../models/study_document_entity.dart';
import '../models/study_plan_task_entity.dart';
import '../models/study_set_entity.dart';
import '../models/user_profile_entity.dart';
import 'isar_scan_data_source_extension.dart';
import 'study_local_data_source.dart';

class IsarStudyLocalDataSource implements StudyLocalDataSource {
  IsarStudyLocalDataSource(this._isar);

  final Isar _isar;

  final _profileController = StreamController<UserProfile?>.broadcast();
  final _studySetsController = StreamController<List<StudySet>>.broadcast();
  final _chatController = StreamController<List<ChatMessage>>.broadcast();
  final _scannedItemsController = StreamController<List<ScannedItem>>.broadcast();
  final _generationResultsController = StreamController<List<GenerationResult>>.broadcast();

  // User Profile
  @override
  Stream<UserProfile?> watchProfile() => _profileController.stream;

  @override
  Future<UserProfile?> loadProfile() async {
    final entity = await _isar.userProfileEntitys.where().findFirst();
    return entity == null ? null : _entityToProfile(entity);
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {
    await _isar.writeTxn(() async {
      await _isar.userProfileEntitys.clear();
      await _isar.userProfileEntitys.put(UserProfileEntity.create(
        userId: profile.id,
        displayName: profile.displayName,
        email: profile.email,
        avatarUrl: profile.avatarUrl,
        activePlan: profile.activePlan,
        focusAreaIndexes: profile.focusAreas.map((e) => e.index).toList(),
        profileBgColor: profile.profileBgColor,
        profileEmoji: profile.profileEmoji,
      ));
    });
    _profileController.add(profile);
  }

  // Study Sets
  @override
  Stream<List<StudySet>> watchStudySets() => _studySetsController.stream;

  @override
  Future<List<StudySet>> loadStudySets() async {
    final entities = await _isar.studySetEntitys.where().findAll();
    return entities.map(_entityToStudySet).toList();
  }

  @override
  Future<void> saveStudySets(List<StudySet> studySets) async {
    await _isar.writeTxn(() async {
      await _isar.studySetEntitys.clear();
      for (final set in studySets) {
        await _isar.studySetEntitys.put(StudySetEntity.create(
          studySetId: set.id,
          title: set.title,
          flashcards: set.flashcards,
          explanations: set.explanations,
          exercises: set.exercises,
          views: set.views,
          borderColor: set.borderColor,
          tagIndex: set.tag.index,
          description: set.description,
        ));
      }
    });
    _studySetsController.add(studySets);
  }

  @override
  Stream<StudySet?> watchStudySet(String id) async* {
    await for (final _ in _studySetsController.stream) {
      final entity = await _isar.studySetEntitys
          .filter()
          .studySetIdEqualTo(id)
          .findFirst();
      yield entity == null ? null : _entityToStudySet(entity);
    }
  }

  @override
  Future<StudySet?> loadStudySet(String id) async {
    final entity = await _isar.studySetEntitys
        .filter()
        .studySetIdEqualTo(id)
        .findFirst();
    return entity == null ? null : _entityToStudySet(entity);
  }

  @override
  Future<void> saveStudySet(StudySet studySet) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.studySetEntitys
          .filter()
          .studySetIdEqualTo(studySet.id)
          .findFirst();

      if (existing != null) {
        await _isar.studySetEntitys.delete(existing.id);
      }

      await _isar.studySetEntitys.put(StudySetEntity.create(
        studySetId: studySet.id,
        title: studySet.title,
        flashcards: studySet.flashcards,
        explanations: studySet.explanations,
        exercises: studySet.exercises,
        views: studySet.views,
        borderColor: studySet.borderColor,
        tagIndex: studySet.tag.index,
        description: studySet.description,
      ));
    });

    final all = await loadStudySets();
    _studySetsController.add(all);
  }

  // Tasks
  @override
  Stream<List<StudyPlanTask>> watchTasksForDate(DateTime date) async* {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    await for (final _ in Stream.periodic(const Duration(seconds: 1))) {
      final entities = await _isar.studyPlanTaskEntitys
          .filter()
          .dueDateBetween(startOfDay, endOfDay)
          .findAll();
      yield entities.map(_entityToTask).toList();
    }
  }

  @override
  Future<List<StudyPlanTask>> loadTasksForDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final entities = await _isar.studyPlanTaskEntitys
        .filter()
        .dueDateBetween(startOfDay, endOfDay)
        .findAll();
    return entities.map(_entityToTask).toList();
  }

  @override
  Future<void> saveTasksForDate(DateTime date, List<StudyPlanTask> tasks) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    await _isar.writeTxn(() async {
      final existing = await _isar.studyPlanTaskEntitys
          .filter()
          .dueDateBetween(startOfDay, endOfDay)
          .findAll();

      for (final entity in existing) {
        await _isar.studyPlanTaskEntitys.delete(entity.id);
      }

      for (final task in tasks) {
        await _isar.studyPlanTaskEntitys.put(StudyPlanTaskEntity.create(
          taskId: task.id,
          title: task.title,
          dueDate: task.dueDate,
          contentTypeIndex: task.contentType.index,
          isCompleted: task.isCompleted,
        ));
      }
    });
  }

  // Documents
  @override
  Stream<List<StudyDocument>> watchDocumentsByType(StudyContentType type) async* {
    await for (final _ in Stream.periodic(const Duration(seconds: 1))) {
      final entities = await _isar.studyDocumentEntitys
          .filter()
          .typeIndexEqualTo(type.index)
          .findAll();
      yield entities.map(_entityToDocument).toList();
    }
  }

  @override
  Future<List<StudyDocument>> loadDocumentsByType(StudyContentType type) async {
    final entities = await _isar.studyDocumentEntitys
        .filter()
        .typeIndexEqualTo(type.index)
        .findAll();
    return entities.map(_entityToDocument).toList();
  }

  @override
  Future<void> saveDocumentsByType(
    StudyContentType type,
    List<StudyDocument> documents,
  ) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.studyDocumentEntitys
          .filter()
          .typeIndexEqualTo(type.index)
          .findAll();

      for (final entity in existing) {
        await _isar.studyDocumentEntitys.delete(entity.id);
      }

      for (final doc in documents) {
        await _isar.studyDocumentEntitys.put(StudyDocumentEntity.create(
          documentId: doc.id,
          title: doc.title,
          sizeLabel: doc.sizeLabel,
          source: doc.source,
          categoryIndex: doc.category.index,
          typeIndex: doc.type.index,
        ));
      }
    });
  }

  // Chat
  @override
  Stream<List<ChatMessage>> watchChatTranscript() => _chatController.stream;

  @override
  Future<List<ChatMessage>> loadChatTranscript() async {
    final entities = await _isar.chatMessageEntitys.where().findAll();
    return entities.map(_entityToChatMessage).toList();
  }

  @override
  Future<void> replaceChatTranscript(List<ChatMessage> messages) async {
    await _isar.writeTxn(() async {
      await _isar.chatMessageEntitys.clear();
      for (final msg in messages) {
        await _isar.chatMessageEntitys.put(ChatMessageEntity.create(
          messageId: msg.id,
          text: msg.text,
          senderIndex: msg.sender.index,
          timestamp: msg.timestamp,
        ));
      }
    });
    _chatController.add(messages);
  }

  @override
  Future<void> appendChatMessage(ChatMessage message) async {
    await _isar.writeTxn(() async {
      await _isar.chatMessageEntitys.put(ChatMessageEntity.create(
        messageId: message.id,
        text: message.text,
        senderIndex: message.sender.index,
        timestamp: message.timestamp,
      ));
    });

    final all = await loadChatTranscript();
    _chatController.add(all);
  }

  // Mappers
  UserProfile _entityToProfile(UserProfileEntity entity) {
    return UserProfile(
      id: entity.userId,
      displayName: entity.displayName,
      email: entity.email,
      avatarUrl: entity.avatarUrl,
      activePlan: entity.activePlan,
      focusAreas: entity.focusAreaIndexes
          .map((i) => StudyMaterialTag.values[i])
          .toList(),
      profileBgColor: entity.profileBgColor,
      profileEmoji: entity.profileEmoji,
    );
  }

  StudySet _entityToStudySet(StudySetEntity entity) {
    return StudySet(
      id: entity.studySetId,
      title: entity.title,
      flashcards: entity.flashcards,
      explanations: entity.explanations,
      exercises: entity.exercises,
      views: entity.views,
      borderColor: entity.borderColor,
      tag: StudyMaterialTag.values[entity.tagIndex],
      description: entity.description,
    );
  }

  StudyPlanTask _entityToTask(StudyPlanTaskEntity entity) {
    return StudyPlanTask(
      id: entity.taskId,
      title: entity.title,
      dueDate: entity.dueDate,
      contentType: StudyContentType.values[entity.contentTypeIndex],
      isCompleted: entity.isCompleted,
    );
  }

  StudyDocument _entityToDocument(StudyDocumentEntity entity) {
    return StudyDocument(
      id: entity.documentId,
      title: entity.title,
      sizeLabel: entity.sizeLabel,
      source: entity.source,
      category: StudyMaterialTag.values[entity.categoryIndex],
      type: StudyContentType.values[entity.typeIndex],
    );
  }

  ChatMessage _entityToChatMessage(ChatMessageEntity entity) {
    return ChatMessage(
      id: entity.messageId,
      text: entity.text,
      sender: ChatSender.values[entity.senderIndex],
      timestamp: entity.timestamp,
    );
  }

  // ==================== Scanned Items ====================

  @override
  Stream<List<ScannedItem>> watchScannedItems() => _scannedItemsController.stream;

  @override
  Future<List<ScannedItem>> loadScannedItems() async {
    return await _isar.loadAllScannedItems();
  }

  @override
  Future<ScannedItem?> loadScannedItem(String id) async {
    return await _isar.loadScannedItemById(id);
  }

  @override
  Future<void> saveScannedItem(ScannedItem item) async {
    await _isar.putScannedItem(item);
    final all = await loadScannedItems();
    _scannedItemsController.add(all);
  }

  @override
  Future<void> deleteScannedItem(String id) async {
    await _isar.removeScannedItem(id);
    final all = await loadScannedItems();
    _scannedItemsController.add(all);
  }

  // ==================== Flashcards ====================

  @override
  Stream<List<Flashcard>> watchFlashcardsByStudySet(String studySetId) async* {
    await for (final _ in Stream.periodic(const Duration(seconds: 1))) {
      final flashcards = await _isar.loadFlashcardsBySet(studySetId);
      yield flashcards;
    }
  }

  @override
  Future<List<Flashcard>> loadFlashcardsByStudySet(String studySetId) async {
    return await _isar.loadFlashcardsBySet(studySetId);
  }

  @override
  Future<void> saveFlashcards(List<Flashcard> flashcards) async {
    await _isar.putFlashcards(flashcards);
  }

  @override
  Future<void> saveFlashcard(Flashcard flashcard) async {
    await _isar.putFlashcard(flashcard);
  }

  @override
  Future<void> deleteFlashcard(String id) async {
    await _isar.removeFlashcard(id);
  }

  // ==================== Explanation Docs ====================

  @override
  Stream<List<ExplanationDoc>> watchExplanationDocsByStudySet(String studySetId) async* {
    await for (final _ in Stream.periodic(const Duration(seconds: 1))) {
      final docs = await _isar.loadExplanationDocsBySet(studySetId);
      yield docs;
    }
  }

  @override
  Future<List<ExplanationDoc>> loadExplanationDocsByStudySet(String studySetId) async {
    return await _isar.loadExplanationDocsBySet(studySetId);
  }

  @override
  Future<void> saveExplanationDocs(List<ExplanationDoc> docs) async {
    await _isar.putExplanationDocs(docs);
  }

  @override
  Future<void> saveExplanationDoc(ExplanationDoc doc) async {
    await _isar.putExplanationDoc(doc);
  }

  @override
  Future<void> deleteExplanationDoc(String id) async {
    await _isar.removeExplanationDoc(id);
  }

  // ==================== Exercises ====================

  @override
  Stream<List<Exercise>> watchExercisesByStudySet(String studySetId) async* {
    await for (final _ in Stream.periodic(const Duration(seconds: 1))) {
      final exercises = await _isar.loadExercisesBySet(studySetId);
      yield exercises;
    }
  }

  @override
  Future<List<Exercise>> loadExercisesByStudySet(String studySetId) async {
    return await _isar.loadExercisesBySet(studySetId);
  }

  @override
  Future<void> saveExercises(List<Exercise> exercises) async {
    await _isar.putExercises(exercises);
  }

  @override
  Future<void> saveExercise(Exercise exercise) async {
    await _isar.putExercise(exercise);
  }

  @override
  Future<void> deleteExercise(String id) async {
    await _isar.removeExercise(id);
  }

  // ==================== Generation Results ====================

  @override
  Stream<List<GenerationResult>> watchPendingGenerationResults() => _generationResultsController.stream;

  @override
  Future<List<GenerationResult>> loadPendingGenerationResults() async {
    return await _isar.loadPendingGenerations();
  }

  @override
  Future<void> saveGenerationResult(GenerationResult result) async {
    await _isar.putGenerationResult(result);
    final all = await loadPendingGenerationResults();
    _generationResultsController.add(all);
  }

  @override
  Future<void> deleteGenerationResult(String id) async {
    await _isar.removeGenerationResult(id);
    final all = await loadPendingGenerationResults();
    _generationResultsController.add(all);
  }

  // ==================== Clear ====================

  @override
  Future<void> clear() async {
    await _isar.writeTxn(() async {
      await _isar.clear();
    });

    _profileController.add(null);
    _studySetsController.add([]);
    _chatController.add([]);
    _scannedItemsController.add([]);
    _generationResultsController.add([]);
  }

  Future<void> dispose() async {
    await _profileController.close();
    await _studySetsController.close();
    await _chatController.close();
    await _scannedItemsController.close();
    await _generationResultsController.close();
  }
}
