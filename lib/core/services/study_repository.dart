import '../models/chat_message.dart';
import '../models/study_content_type.dart';
import '../models/study_document.dart';
import '../models/study_plan_task.dart';
import '../models/study_set.dart';
import '../models/user_profile.dart';

abstract class StudyRepository {
  Stream<UserProfile?> watchProfile();
  Future<UserProfile> fetchProfile({bool forceRefresh = false});

  Stream<List<StudySet>> watchStudySets();
  Future<List<StudySet>> fetchStudySets({bool forceRefresh = false});

  Stream<StudySet?> watchStudySetById(String id);
  Future<StudySet?> fetchStudySetById(
    String id, {
    bool forceRefresh = false,
  });

  Stream<List<StudyPlanTask>> watchTasksForDate(DateTime date);
  Future<List<StudyPlanTask>> fetchTasksForDate(
    DateTime date, {
    bool forceRefresh = false,
  });

  Stream<List<StudyDocument>> watchDocumentsByType(StudyContentType type);
  Future<List<StudyDocument>> fetchDocumentsByType(
    StudyContentType type, {
    bool forceRefresh = false,
  });

  Stream<List<ChatMessage>> watchChatTranscript();
  Future<List<ChatMessage>> loadInitialChatTranscript({bool forceRefresh = false});
  Future<void> replaceChatTranscript(List<ChatMessage> messages);
  Future<void> appendChatMessage(ChatMessage message);
  Future<void> updateChatMessage(ChatMessage message);
  Future<ChatMessage> generateBotReply(String prompt, {String? imageUrl});
}
