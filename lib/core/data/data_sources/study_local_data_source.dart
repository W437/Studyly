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

abstract class StudyLocalDataSource {
  Stream<UserProfile?> watchProfile();
  Future<UserProfile?> loadProfile();
  Future<void> saveProfile(UserProfile profile);

  Stream<List<StudySet>> watchStudySets();
  Future<List<StudySet>> loadStudySets();
  Future<void> saveStudySets(List<StudySet> studySets);

  Stream<StudySet?> watchStudySet(String id);
  Future<StudySet?> loadStudySet(String id);
  Future<void> saveStudySet(StudySet studySet);

  Stream<List<StudyPlanTask>> watchTasksForDate(DateTime date);
  Future<List<StudyPlanTask>> loadTasksForDate(DateTime date);
  Future<void> saveTasksForDate(DateTime date, List<StudyPlanTask> tasks);

  Stream<List<StudyDocument>> watchDocumentsByType(StudyContentType type);
  Future<List<StudyDocument>> loadDocumentsByType(StudyContentType type);
  Future<void> saveDocumentsByType(
    StudyContentType type,
    List<StudyDocument> documents,
  );

  Stream<List<ChatMessage>> watchChatTranscript();
  Future<List<ChatMessage>> loadChatTranscript();
  Future<void> replaceChatTranscript(List<ChatMessage> messages);
  Future<void> appendChatMessage(ChatMessage message);
  Future<void> updateChatMessage(ChatMessage message);

  // Scanned items
  Stream<List<ScannedItem>> watchScannedItems();
  Future<List<ScannedItem>> loadScannedItems();
  Future<ScannedItem?> loadScannedItem(String id);
  Future<void> saveScannedItem(ScannedItem item);
  Future<void> deleteScannedItem(String id);

  // Flashcards
  Stream<List<Flashcard>> watchFlashcardsByStudySet(String studySetId);
  Future<List<Flashcard>> loadFlashcardsByStudySet(String studySetId);
  Future<void> saveFlashcards(List<Flashcard> flashcards);
  Future<void> saveFlashcard(Flashcard flashcard);
  Future<void> deleteFlashcard(String id);

  // Explanation docs
  Stream<List<ExplanationDoc>> watchExplanationDocsByStudySet(String studySetId);
  Future<List<ExplanationDoc>> loadExplanationDocsByStudySet(String studySetId);
  Future<void> saveExplanationDocs(List<ExplanationDoc> docs);
  Future<void> saveExplanationDoc(ExplanationDoc doc);
  Future<void> deleteExplanationDoc(String id);

  // Exercises
  Stream<List<Exercise>> watchExercisesByStudySet(String studySetId);
  Future<List<Exercise>> loadExercisesByStudySet(String studySetId);
  Future<void> saveExercises(List<Exercise> exercises);
  Future<void> saveExercise(Exercise exercise);
  Future<void> deleteExercise(String id);

  // Generation results (offline queue)
  Stream<List<GenerationResult>> watchPendingGenerationResults();
  Future<List<GenerationResult>> loadPendingGenerationResults();
  Future<void> saveGenerationResult(GenerationResult result);
  Future<void> deleteGenerationResult(String id);

  Future<void> clear();
}
