import 'dart:async';
import 'dart:math';

import '../models/chat_message.dart';
import '../models/study_content_type.dart';
import '../models/study_document.dart';
import '../models/study_plan_task.dart';
import '../models/study_set.dart';
import '../models/user_profile.dart';
import 'study_repository.dart';

class MockStudyRepository implements StudyRepository {
  MockStudyRepository() {
    _seedTasks();
  }

  static const _delay = Duration(milliseconds: 250);
  final _random = Random(14);

  late final List<StudySet> _studySets = _buildStudySets();
  final Map<DateTime, List<StudyPlanTask>> _tasksByDate = {};
  late final Map<StudyContentType, List<StudyDocument>> _documentsByType =
      _buildDocuments();

  UserProfile get _profile => const UserProfile(
    id: 'user-1',
    displayName: 'Andrew Ainsley',
    email: 'andrew.ainsley@yourdomain.com',
    avatarUrl: 'https://i.pravatar.cc/150?img=12',
    activePlan: 'Pro',
    focusAreas: [
      StudyMaterialTag.biology,
      StudyMaterialTag.computerScience,
      StudyMaterialTag.mathematics,
    ],
  );

  @override
  Future<UserProfile> fetchProfile() async {
    await Future<void>.delayed(_delay);
    return _profile;
  }

  @override
  Future<List<StudySet>> fetchStudySets() async {
    await Future<void>.delayed(_delay);
    return _studySets;
  }

  @override
  Future<StudySet?> fetchStudySetById(String id) async {
    await Future<void>.delayed(_delay);
    return _studySets.firstWhere(
      (set) => set.id == id,
      orElse: () => _studySets.firstWhere(
        (set) => set.title.toLowerCase() == id.toLowerCase(),
        orElse: () => _studySets.first,
      ),
    );
  }

  @override
  Future<List<StudyPlanTask>> fetchTasksForDate(DateTime date) async {
    await Future<void>.delayed(_delay);
    final normalized = _normalize(date);
    return _tasksByDate[normalized] ?? const [];
  }

  @override
  Future<List<StudyDocument>> fetchDocumentsByType(
    StudyContentType type,
  ) async {
    await Future<void>.delayed(_delay);
    return _documentsByType[type] ?? const [];
  }

  @override
  Future<List<ChatMessage>> loadInitialChatTranscript() async {
    await Future<void>.delayed(_delay);
    return [
      ChatMessage(
        id: 'init-1',
        text: 'Hello! How can I assist you with your studies today?',
        sender: ChatSender.bot,
        timestamp: DateTime.now(),
      ),
    ];
  }

  @override
  Future<ChatMessage> generateBotReply(String prompt) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final lowercase = prompt.toLowerCase();
    final intro = lowercase.contains('plan')
        ? 'Here is a quick study plan you can follow:'
        : lowercase.contains('flashcard')
        ? 'Let me break that down into flashcard-sized bites:'
        : 'Here\'s something that should help:';

    final suggestions = <String>[
      'Summarize key points in your own words to boost memory retention.',
      'Create a mini quiz covering the toughest concepts you encounter.',
      'Alternate between explanations and practice exercises to stay engaged.',
    ];
    final tip = suggestions[_random.nextInt(suggestions.length)];

    final reply = '$intro\n\n• ${_capitalize(prompt)}\n• $tip';
    return ChatMessage(
      id: 'bot-${DateTime.now().millisecondsSinceEpoch}',
      text: reply,
      sender: ChatSender.bot,
      timestamp: DateTime.now(),
    );
  }

  void _seedTasks() {
    final today = _normalize(DateTime.now());
    for (int offset = -14; offset <= 14; offset++) {
      final date = _normalize(today.add(Duration(days: offset)));
      final tasks = <StudyPlanTask>[
        _makeTask(
          date,
          'Review ${_subjectForOffset(offset)} flashcards',
          StudyContentType.flashcards,
          offset < 0 && offset % 2 == 0,
        ),
        _makeTask(
          date,
          'Read explanation on ${_subjectForOffset(offset + 2)}',
          StudyContentType.explanations,
          offset < 0 && offset % 3 == 0,
        ),
        if (offset.abs().isEven)
          _makeTask(
            date,
            'Complete practice set ${_random.nextInt(20) + 1}',
            StudyContentType.exercises,
            offset < 0 && offset % 4 == 0,
          ),
      ];
      _tasksByDate[date] = tasks;
    }
  }

  Map<StudyContentType, List<StudyDocument>> _buildDocuments() {
    return {
      StudyContentType.flashcards: [
        const StudyDocument(
          id: 'doc-1',
          title: 'Cell Division Concepts',
          sizeLabel: '1.2 MB',
          source: 'from Microbiology',
          category: StudyMaterialTag.biology,
          type: StudyContentType.flashcards,
        ),
        const StudyDocument(
          id: 'doc-2',
          title: 'Data Structures: Flash Review',
          sizeLabel: '2.3 MB',
          source: 'from Computer Vision',
          category: StudyMaterialTag.computerScience,
          type: StudyContentType.flashcards,
        ),
      ],
      StudyContentType.explanations: [
        const StudyDocument(
          id: 'doc-3',
          title: 'Fluid Mechanics: Basic Principles',
          sizeLabel: '1.6 MB',
          source: 'from Engineering School',
          category: StudyMaterialTag.engineering,
          type: StudyContentType.explanations,
        ),
        const StudyDocument(
          id: 'doc-4',
          title: 'Thermodynamics: Laws at Work',
          sizeLabel: '2.1 MB',
          source: 'from Physics for Dynamics',
          category: StudyMaterialTag.physics,
          type: StudyContentType.explanations,
        ),
      ],
      StudyContentType.exercises: [
        const StudyDocument(
          id: 'doc-5',
          title: 'Algebraic Inequalities Practice',
          sizeLabel: '1.8 MB',
          source: 'from Mathematics',
          category: StudyMaterialTag.mathematics,
          type: StudyContentType.exercises,
        ),
        const StudyDocument(
          id: 'doc-6',
          title: 'Entrepreneurship: Case Exercises',
          sizeLabel: '1.5 MB',
          source: 'from Business Strategy',
          category: StudyMaterialTag.business,
          type: StudyContentType.exercises,
        ),
      ],
    };
  }

  List<StudySet> _buildStudySets() {
    return const [
      StudySet(
        id: 'microbiology',
        title: 'Microbiology',
        flashcards: 246,
        explanations: 195,
        exercises: 163,
        views: '20.6k',
        borderColor: 0xFF42A5F5,
        tag: StudyMaterialTag.biology,
        description:
            'Deep dive into bacteria, viruses, fungi, and immune system responses with curated flashcards and explanations.',
      ),
      StudySet(
        id: 'artificial-intelligence',
        title: 'Artificial Intelligence',
        flashcards: 305,
        explanations: 294,
        exercises: 201,
        views: '24.3k',
        borderColor: 0xFFEF5350,
        tag: StudyMaterialTag.computerScience,
        description:
            'Explore machine learning concepts, key algorithms, and practice scenarios for modern AI applications.',
      ),
      StudySet(
        id: 'entrepreneurship',
        title: 'Entrepreneurship',
        flashcards: 260,
        explanations: 154,
        exercises: 182,
        views: '19.8k',
        borderColor: 0xFF66BB6A,
        tag: StudyMaterialTag.business,
        description:
            'Business modelling, pitching fundamentals, and financial planning essentials gathered in one place.',
      ),
      StudySet(
        id: 'political-science',
        title: 'Political Science',
        flashcards: 194,
        explanations: 126,
        exercises: 109,
        views: '15.2k',
        borderColor: 0xFF9C27B0,
        tag: StudyMaterialTag.socialScience,
        description:
            'Understand political theories, governance structures, and policy analysis techniques with guided materials.',
      ),
      StudySet(
        id: 'cell-biology',
        title: 'Cell Biology',
        flashcards: 180,
        explanations: 112,
        exercises: 90,
        views: '11.4k',
        borderColor: 0xFF4DB6AC,
        tag: StudyMaterialTag.biology,
        description:
            'Structure and processes of cells from membranes to mitosis, backed with visuals and practice questions.',
      ),
    ];
  }

  StudyPlanTask _makeTask(
    DateTime date,
    String title,
    StudyContentType type,
    bool isCompleted,
  ) {
    return StudyPlanTask(
      id: '${date.millisecondsSinceEpoch}-${title.hashCode}',
      title: title,
      dueDate: date,
      contentType: type,
      isCompleted: isCompleted,
    );
  }

  DateTime _normalize(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String _subjectForOffset(int offset) {
    final subjects = [
      'Cell Biology',
      'Data Structures',
      'Fluid Mechanics',
      'Entrepreneurship',
      'Thermodynamics',
      'Political Theory',
      'Microeconomics',
    ];
    final index = offset.abs() % subjects.length;
    return subjects[index];
  }

  String _capitalize(String input) {
    if (input.isEmpty) {
      return input;
    }
    return input[0].toUpperCase() + input.substring(1);
  }
}
