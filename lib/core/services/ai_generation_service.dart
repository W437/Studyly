import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class FlashcardProposal {
  const FlashcardProposal({
    required this.front,
    required this.back,
    this.hint,
    this.difficulty = 3,
  });

  final String front;
  final String back;
  final String? hint;
  final int difficulty;

  factory FlashcardProposal.fromJson(Map<String, dynamic> json) {
    return FlashcardProposal(
      front: json['front'] as String,
      back: json['back'] as String,
      hint: json['hint'] as String?,
      difficulty: (json['difficulty'] as int?) ?? 3,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'front': front,
      'back': back,
      'hint': hint,
      'difficulty': difficulty,
    };
  }
}

class ExplanationProposal {
  const ExplanationProposal({
    required this.title,
    required this.summary,
    required this.keyPoints,
    required this.content,
  });

  final String title;
  final String summary;
  final List<String> keyPoints;
  final String content;

  factory ExplanationProposal.fromJson(Map<String, dynamic> json) {
    return ExplanationProposal(
      title: json['title'] as String,
      summary: json['summary'] as String,
      keyPoints: (json['key_points'] as List<dynamic>).cast<String>(),
      content: json['content'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'summary': summary,
      'key_points': keyPoints,
      'content': content,
    };
  }
}

class ExerciseProposal {
  const ExerciseProposal({
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
    this.difficulty = 3,
  });

  final String question;
  final List<String> options;
  final String correctAnswer;
  final String explanation;
  final int difficulty;

  factory ExerciseProposal.fromJson(Map<String, dynamic> json) {
    return ExerciseProposal(
      question: json['question'] as String,
      options: (json['options'] as List<dynamic>).cast<String>(),
      correctAnswer: json['correct_answer'] as String,
      explanation: json['explanation'] as String,
      difficulty: (json['difficulty'] as int?) ?? 3,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'question': question,
      'options': options,
      'correct_answer': correctAnswer,
      'explanation': explanation,
      'difficulty': difficulty,
    };
  }
}

class AIGenerationService {
  AIGenerationService({required SupabaseClient supabaseClient})
      : _supabase = supabaseClient;

  final SupabaseClient _supabase;

  /// Generate flashcards from text/image
  Future<List<FlashcardProposal>> generateFlashcards({
    required String text,
    String? imageRef,
    String? subject,
    String? level,
    String? language,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'ai_generate_flashcards',
        body: {
          'text': text,
          'image_ref': imageRef,
          'subject': subject,
          'level': level,
          'language': language ?? 'en',
        },
      );

      if (response.status != 200) {
        throw Exception('Failed to generate flashcards: ${response.status}');
      }

      final data = response.data as Map<String, dynamic>;
      final proposals = (data['flashcards'] as List<dynamic>)
          .map((item) => FlashcardProposal.fromJson(item as Map<String, dynamic>))
          .toList();

      return proposals;
    } catch (e) {
      rethrow;
    }
  }

  /// Generate explanation/summary from text/image
  Future<ExplanationProposal> generateExplanation({
    required String text,
    String? imageRef,
    String? subject,
    String? level,
    String? language,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'ai_generate_summary',
        body: {
          'text': text,
          'image_ref': imageRef,
          'subject': subject,
          'level': level,
          'language': language ?? 'en',
        },
      );

      if (response.status != 200) {
        throw Exception('Failed to generate explanation: ${response.status}');
      }

      final data = response.data as Map<String, dynamic>;
      return ExplanationProposal.fromJson(data);
    } catch (e) {
      rethrow;
    }
  }

  /// Generate MCQ exercises from text/image
  Future<List<ExerciseProposal>> generateExercises({
    required String text,
    String? imageRef,
    String? subject,
    String? level,
    int count = 5,
    String? language,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'ai_generate_mcqs',
        body: {
          'text': text,
          'image_ref': imageRef,
          'subject': subject,
          'level': level,
          'count': count,
          'language': language ?? 'en',
        },
      );

      if (response.status != 200) {
        throw Exception('Failed to generate exercises: ${response.status}');
      }

      final data = response.data as Map<String, dynamic>;
      final proposals = (data['exercises'] as List<dynamic>)
          .map((item) => ExerciseProposal.fromJson(item as Map<String, dynamic>))
          .toList();

      return proposals;
    } catch (e) {
      rethrow;
    }
  }
}
