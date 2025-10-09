import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/chat_message.dart';
import '../../models/study_content_type.dart';
import '../../models/study_document.dart';
import '../../models/study_plan_task.dart';
import '../../models/study_set.dart';
import '../../models/user_profile.dart';
import 'study_remote_data_source.dart';

class SupabaseStudyRemoteDataSource implements StudyRemoteDataSource {
  SupabaseStudyRemoteDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<UserProfile> fetchProfile() async {
    final userId = _client.auth.currentUser?.id;
    debugPrint('🔍 Fetching profile, userId: $userId');
    if (userId == null) {
      debugPrint('❌ No authenticated user found');
      throw Exception('User not authenticated');
    }

    final response = await _client
        .from('user_profiles')
        .select()
        .eq('user_id', userId)
        .single();

    return UserProfile(
      id: response['user_id'] as String,
      displayName: response['display_name'] as String,
      email: response['email'] as String,
      avatarUrl: response['avatar_url'] as String,
      activePlan: response['active_plan'] as String,
      focusAreas: (response['focus_areas'] as List<dynamic>)
          .map((e) => StudyMaterialTag.values[e as int])
          .toList(),
      profileBgColor: response['profile_bg_color'] as String? ?? '#6366F1',
      profileEmoji: response['profile_emoji'] as String? ?? '😊',
    );
  }

  @override
  Future<List<StudySet>> fetchStudySets() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final response = await _client
        .from('study_sets')
        .select()
        .eq('user_id', userId);

    return (response as List<dynamic>).map((json) {
      return StudySet(
        id: json['id'] as String,
        title: json['title'] as String,
        flashcards: json['flashcards'] as int,
        explanations: json['explanations'] as int,
        exercises: json['exercises'] as int,
        views: json['views'] as String,
        borderColor: json['border_color'] as int,
        tag: StudyMaterialTag.values[json['tag'] as int],
        description: json['description'] as String,
      );
    }).toList();
  }

  @override
  Future<StudySet?> fetchStudySetById(String id) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final response = await _client
        .from('study_sets')
        .select()
        .eq('id', id)
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) return null;

    return StudySet(
      id: response['id'] as String,
      title: response['title'] as String,
      flashcards: response['flashcards'] as int,
      explanations: response['explanations'] as int,
      exercises: response['exercises'] as int,
      views: response['views'] as String,
      borderColor: response['border_color'] as int,
      tag: StudyMaterialTag.values[response['tag'] as int],
      description: response['description'] as String,
    );
  }

  @override
  Future<List<StudyPlanTask>> fetchTasksForDate(DateTime date) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final response = await _client
        .from('study_plan_tasks')
        .select()
        .eq('user_id', userId)
        .gte('due_date', startOfDay.toIso8601String())
        .lt('due_date', endOfDay.toIso8601String());

    return (response as List<dynamic>).map((json) {
      return StudyPlanTask(
        id: json['id'] as String,
        title: json['title'] as String,
        dueDate: DateTime.parse(json['due_date'] as String),
        contentType: StudyContentType.values[json['content_type'] as int],
        isCompleted: json['is_completed'] as bool,
      );
    }).toList();
  }

  @override
  Future<List<StudyDocument>> fetchDocumentsByType(StudyContentType type) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final response = await _client
        .from('study_documents')
        .select()
        .eq('user_id', userId)
        .eq('type', type.index);

    return (response as List<dynamic>).map((json) {
      return StudyDocument(
        id: json['id'] as String,
        title: json['title'] as String,
        sizeLabel: json['size_label'] as String,
        source: json['source'] as String,
        category: StudyMaterialTag.values[json['category'] as int],
        type: StudyContentType.values[json['type'] as int],
      );
    }).toList();
  }

  @override
  Future<List<ChatMessage>> loadInitialChatTranscript() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final response = await _client
        .from('chat_messages')
        .select()
        .eq('user_id', userId)
        .order('timestamp', ascending: true);

    return (response as List<dynamic>).map((json) {
      return ChatMessage(
        id: json['id'] as String,
        text: json['text'] as String,
        sender: ChatSender.values[json['sender'] as int],
        timestamp: DateTime.parse(json['timestamp'] as String),
        imageUrl: json['image_url'] as String?,
      );
    }).toList();
  }

  @override
  Future<ChatMessage> generateBotReply(String prompt, {String? imageUrl}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Call Edge Function for AI response
    final response = await _client.functions.invoke(
      'generate-chat-response',
      body: {
        'prompt': prompt,
        'user_id': userId,
        if (imageUrl != null) 'image_url': imageUrl,
      },
    );

    final data = response.data as Map<String, dynamic>;

    return ChatMessage(
      id: data['id'] as String,
      text: data['text'] as String,
      sender: ChatSender.bot,
      timestamp: DateTime.parse(data['timestamp'] as String),
    );
  }
}
