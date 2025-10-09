import '../models/chat_message.dart';
import '../models/study_content_type.dart';
import '../models/study_document.dart';
import '../models/study_plan_task.dart';
import '../models/study_set.dart';
import '../models/user_profile.dart';

abstract class StudyRepository {
  Future<UserProfile> fetchProfile();
  Future<List<StudySet>> fetchStudySets();
  Future<StudySet?> fetchStudySetById(String id);
  Future<List<StudyPlanTask>> fetchTasksForDate(DateTime date);
  Future<List<StudyDocument>> fetchDocumentsByType(StudyContentType type);
  Future<List<ChatMessage>> loadInitialChatTranscript();
  Future<ChatMessage> generateBotReply(String prompt);
}
