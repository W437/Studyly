import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/services/study_repository.dart';

typedef ChatState = List<ChatMessage>;

class ChatController extends Notifier<ChatState> {
  int _replyToken = 0;

  StudyRepository get _repository => ref.read(studyRepositoryProvider);

  @override
  ChatState build() {
    _initialize();
    return const [];
  }

  Future<void> _initialize() async {
    final initialMessages = await _repository.loadInitialChatTranscript();
    if (!ref.mounted) {
      return;
    }
    state = initialMessages;
  }

  Future<void> sendUserMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final userMessage = ChatMessage(
      id: 'user-${DateTime.now().millisecondsSinceEpoch}',
      text: trimmed,
      sender: ChatSender.user,
      timestamp: DateTime.now(),
    );
    state = [...state, userMessage];
    await _enqueueBotReply(trimmed);
  }

  Future<void> clearConversation() async {
    _replyToken++;
    state = const [];
    await _initialize();
  }

  Future<void> _enqueueBotReply(String prompt) async {
    final placeholder = ChatMessage(
      id: 'bot-placeholder-${DateTime.now().millisecondsSinceEpoch}',
      text: 'Thinking...',
      sender: ChatSender.bot,
      timestamp: DateTime.now(),
      isProcessing: true,
    );
    state = [...state, placeholder];

    final currentToken = ++_replyToken;
    final reply = await _repository.generateBotReply(prompt);
    if (!ref.mounted || currentToken != _replyToken) {
      return;
    }

    state = [
      for (final message in state)
        if (message.id == placeholder.id) reply else message,
    ];
  }
}

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);
