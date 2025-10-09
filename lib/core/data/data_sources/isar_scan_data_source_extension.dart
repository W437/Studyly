import 'dart:async';
import 'dart:convert';

import 'package:isar/isar.dart';

import '../../models/exercise.dart';
import '../../models/explanation_doc.dart';
import '../../models/flashcard.dart';
import '../../models/generation_result.dart';
import '../../models/scanned_item.dart';
import '../models/exercise_entity.dart';
import '../models/explanation_doc_entity.dart';
import '../models/flashcard_entity.dart';
import '../models/generation_result_entity.dart';
import '../models/scanned_item_entity.dart';

/// Extension for scan-related operations in IsarStudyLocalDataSource
/// This file contains implementations for scanned items, flashcards,
/// explanation docs, exercises, and generation results.
extension IsarScanDataSourceExtension on Isar {
  // ==================== Scanned Items ====================

  Future<List<ScannedItem>> loadAllScannedItems() async {
    final entities = await scannedItemEntitys.where().findAll();
    return entities.map(_scannedItemEntityToModel).toList();
  }

  Future<ScannedItem?> loadScannedItemById(String id) async {
    final entity = await scannedItemEntitys
        .filter()
        .itemIdEqualTo(id)
        .findFirst();
    return entity == null ? null : _scannedItemEntityToModel(entity);
  }

  Future<void> putScannedItem(ScannedItem item) async {
    await writeTxn(() async {
      final existing = await scannedItemEntitys
          .filter()
          .itemIdEqualTo(item.id)
          .findFirst();

      if (existing != null) {
        await scannedItemEntitys.delete(existing.id);
      }

      await scannedItemEntitys.put(ScannedItemEntity.create(
        itemId: item.id,
        userId: item.userId,
        localImagePath: item.localImagePath,
        remoteImageUrl: item.remoteImageUrl,
        statusIndex: item.status.index,
        ocrText: item.ocrText,
        selectedAction: item.selectedAction,
        errorMessage: item.errorMessage,
        createdAt: item.createdAt,
      ));
    });
  }

  Future<void> removeScannedItem(String id) async {
    await writeTxn(() async {
      final entity = await scannedItemEntitys
          .filter()
          .itemIdEqualTo(id)
          .findFirst();
      if (entity != null) {
        await scannedItemEntitys.delete(entity.id);
      }
    });
  }

  // ==================== Flashcards ====================

  Future<List<Flashcard>> loadFlashcardsBySet(String studySetId) async {
    final entities = await flashcardEntitys
        .filter()
        .studySetIdEqualTo(studySetId)
        .findAll();
    return entities.map(_flashcardEntityToModel).toList();
  }

  Future<void> putFlashcards(List<Flashcard> flashcards) async {
    await writeTxn(() async {
      for (final flashcard in flashcards) {
        final existing = await flashcardEntitys
            .filter()
            .flashcardIdEqualTo(flashcard.id)
            .findFirst();

        if (existing != null) {
          await flashcardEntitys.delete(existing.id);
        }

        await flashcardEntitys.put(_flashcardModelToEntity(flashcard));
      }
    });
  }

  Future<void> putFlashcard(Flashcard flashcard) async {
    await writeTxn(() async {
      final existing = await flashcardEntitys
          .filter()
          .flashcardIdEqualTo(flashcard.id)
          .findFirst();

      if (existing != null) {
        await flashcardEntitys.delete(existing.id);
      }

      await flashcardEntitys.put(_flashcardModelToEntity(flashcard));
    });
  }

  Future<void> removeFlashcard(String id) async {
    await writeTxn(() async {
      final entity = await flashcardEntitys
          .filter()
          .flashcardIdEqualTo(id)
          .findFirst();
      if (entity != null) {
        await flashcardEntitys.delete(entity.id);
      }
    });
  }

  // ==================== Explanation Docs ====================

  Future<List<ExplanationDoc>> loadExplanationDocsBySet(String studySetId) async {
    final entities = await explanationDocEntitys
        .filter()
        .studySetIdEqualTo(studySetId)
        .findAll();
    return entities.map(_explanationDocEntityToModel).toList();
  }

  Future<void> putExplanationDocs(List<ExplanationDoc> docs) async {
    await writeTxn(() async {
      for (final doc in docs) {
        final existing = await explanationDocEntitys
            .filter()
            .docIdEqualTo(doc.id)
            .findFirst();

        if (existing != null) {
          await explanationDocEntitys.delete(existing.id);
        }

        await explanationDocEntitys.put(_explanationDocModelToEntity(doc));
      }
    });
  }

  Future<void> putExplanationDoc(ExplanationDoc doc) async {
    await writeTxn(() async {
      final existing = await explanationDocEntitys
          .filter()
          .docIdEqualTo(doc.id)
          .findFirst();

      if (existing != null) {
        await explanationDocEntitys.delete(existing.id);
      }

      await explanationDocEntitys.put(_explanationDocModelToEntity(doc));
    });
  }

  Future<void> removeExplanationDoc(String id) async {
    await writeTxn(() async {
      final entity = await explanationDocEntitys
          .filter()
          .docIdEqualTo(id)
          .findFirst();
      if (entity != null) {
        await explanationDocEntitys.delete(entity.id);
      }
    });
  }

  // ==================== Exercises ====================

  Future<List<Exercise>> loadExercisesBySet(String studySetId) async {
    final entities = await exerciseEntitys
        .filter()
        .studySetIdEqualTo(studySetId)
        .findAll();
    return entities.map(_exerciseEntityToModel).toList();
  }

  Future<void> putExercises(List<Exercise> exercises) async {
    await writeTxn(() async {
      for (final exercise in exercises) {
        final existing = await exerciseEntitys
            .filter()
            .exerciseIdEqualTo(exercise.id)
            .findFirst();

        if (existing != null) {
          await exerciseEntitys.delete(existing.id);
        }

        await exerciseEntitys.put(_exerciseModelToEntity(exercise));
      }
    });
  }

  Future<void> putExercise(Exercise exercise) async {
    await writeTxn(() async {
      final existing = await exerciseEntitys
          .filter()
          .exerciseIdEqualTo(exercise.id)
          .findFirst();

      if (existing != null) {
        await exerciseEntitys.delete(existing.id);
      }

      await exerciseEntitys.put(_exerciseModelToEntity(exercise));
    });
  }

  Future<void> removeExercise(String id) async {
    await writeTxn(() async {
      final entity = await exerciseEntitys
          .filter()
          .exerciseIdEqualTo(id)
          .findFirst();
      if (entity != null) {
        await exerciseEntitys.delete(entity.id);
      }
    });
  }

  // ==================== Generation Results ====================

  Future<List<GenerationResult>> loadPendingGenerations() async {
    final entities = await generationResultEntitys
        .filter()
        .statusIndexEqualTo(GenerationStatus.pending.index)
        .or()
        .statusIndexEqualTo(GenerationStatus.processing.index)
        .findAll();
    return entities.map(_generationResultEntityToModel).toList();
  }

  Future<void> putGenerationResult(GenerationResult result) async {
    await writeTxn(() async {
      final existing = await generationResultEntitys
          .filter()
          .resultIdEqualTo(result.id)
          .findFirst();

      if (existing != null) {
        await generationResultEntitys.delete(existing.id);
      }

      await generationResultEntitys.put(GenerationResultEntity.create(
        resultId: result.id,
        userId: result.userId,
        scannedItemId: result.scannedItemId,
        typeIndex: result.type.index,
        statusIndex: result.status.index,
        inputText: result.inputText,
        imageUrl: result.imageUrl,
        resultJson: result.result != null ? jsonEncode(result.result) : null,
        errorMessage: result.errorMessage,
        createdAt: result.createdAt,
        completedAt: result.completedAt,
      ));
    });
  }

  Future<void> removeGenerationResult(String id) async {
    await writeTxn(() async {
      final entity = await generationResultEntitys
          .filter()
          .resultIdEqualTo(id)
          .findFirst();
      if (entity != null) {
        await generationResultEntitys.delete(entity.id);
      }
    });
  }

  // ==================== Mappers ====================

  ScannedItem _scannedItemEntityToModel(ScannedItemEntity entity) {
    return ScannedItem(
      id: entity.itemId,
      userId: entity.userId,
      localImagePath: entity.localImagePath,
      remoteImageUrl: entity.remoteImageUrl,
      status: ScanStatus.values[entity.statusIndex],
      ocrText: entity.ocrText,
      selectedAction: entity.selectedAction,
      errorMessage: entity.errorMessage,
      createdAt: entity.createdAt,
    );
  }

  Flashcard _flashcardEntityToModel(FlashcardEntity entity) {
    SRSState? srsState;
    if (entity.srsEaseFactor != null &&
        entity.srsInterval != null &&
        entity.srsRepetitions != null &&
        entity.srsNextReviewDate != null) {
      srsState = SRSState(
        easeFactor: entity.srsEaseFactor!,
        interval: entity.srsInterval!,
        repetitions: entity.srsRepetitions!,
        nextReviewDate: entity.srsNextReviewDate!,
        lastReviewDate: entity.srsLastReviewDate,
      );
    }

    return Flashcard(
      id: entity.flashcardId,
      studySetId: entity.studySetId,
      front: entity.front,
      back: entity.back,
      hint: entity.hint,
      difficulty: entity.difficulty,
      srsState: srsState,
      createdAt: entity.createdAt,
    );
  }

  FlashcardEntity _flashcardModelToEntity(Flashcard flashcard) {
    return FlashcardEntity.create(
      flashcardId: flashcard.id,
      studySetId: flashcard.studySetId,
      front: flashcard.front,
      back: flashcard.back,
      hint: flashcard.hint,
      difficulty: flashcard.difficulty,
      createdAt: flashcard.createdAt,
      srsEaseFactor: flashcard.srsState?.easeFactor,
      srsInterval: flashcard.srsState?.interval,
      srsRepetitions: flashcard.srsState?.repetitions,
      srsNextReviewDate: flashcard.srsState?.nextReviewDate,
      srsLastReviewDate: flashcard.srsState?.lastReviewDate,
    );
  }

  ExplanationDoc _explanationDocEntityToModel(ExplanationDocEntity entity) {
    return ExplanationDoc(
      id: entity.docId,
      studySetId: entity.studySetId,
      title: entity.title,
      summary: entity.summary,
      keyPoints: entity.keyPoints,
      content: entity.content,
      sourceImageUrl: entity.sourceImageUrl,
      createdAt: entity.createdAt,
    );
  }

  ExplanationDocEntity _explanationDocModelToEntity(ExplanationDoc doc) {
    return ExplanationDocEntity.create(
      docId: doc.id,
      studySetId: doc.studySetId,
      title: doc.title,
      summary: doc.summary,
      keyPoints: doc.keyPoints,
      content: doc.content,
      sourceImageUrl: doc.sourceImageUrl,
      createdAt: doc.createdAt,
    );
  }

  Exercise _exerciseEntityToModel(ExerciseEntity entity) {
    return Exercise(
      id: entity.exerciseId,
      studySetId: entity.studySetId,
      question: entity.question,
      options: entity.options,
      correctAnswer: entity.correctAnswer,
      explanation: entity.explanation,
      type: ExerciseType.values[entity.typeIndex],
      difficulty: entity.difficulty,
      userAnswer: entity.userAnswer,
      isCorrect: entity.isCorrect,
      createdAt: entity.createdAt,
    );
  }

  ExerciseEntity _exerciseModelToEntity(Exercise exercise) {
    return ExerciseEntity.create(
      exerciseId: exercise.id,
      studySetId: exercise.studySetId,
      question: exercise.question,
      options: exercise.options,
      correctAnswer: exercise.correctAnswer,
      explanation: exercise.explanation,
      typeIndex: exercise.type.index,
      difficulty: exercise.difficulty,
      userAnswer: exercise.userAnswer,
      isCorrect: exercise.isCorrect,
      createdAt: exercise.createdAt,
    );
  }

  GenerationResult _generationResultEntityToModel(GenerationResultEntity entity) {
    Map<String, dynamic>? result;
    if (entity.resultJson != null) {
      result = jsonDecode(entity.resultJson!) as Map<String, dynamic>;
    }

    return GenerationResult(
      id: entity.resultId,
      userId: entity.userId,
      scannedItemId: entity.scannedItemId,
      type: GenerationType.values[entity.typeIndex],
      status: GenerationStatus.values[entity.statusIndex],
      inputText: entity.inputText,
      imageUrl: entity.imageUrl,
      result: result,
      errorMessage: entity.errorMessage,
      createdAt: entity.createdAt,
      completedAt: entity.completedAt,
    );
  }
}
