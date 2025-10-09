import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/services/study_repository.dart';

typedef ChatState = AsyncValue<List<ChatMessage>>;

class ChatController extends Notifier<ChatState> {
  int _replyToken = 0;
  StreamSubscription<List<ChatMessage>>? _subscription;

  StudyRepository get _repository => ref.read(studyRepositoryProvider);

  @override
  ChatState build() {
    state = const AsyncValue.loading();

    _subscription = _repository.watchChatTranscript().listen(
      (messages) {
        state = AsyncValue.data(List<ChatMessage>.unmodifiable(messages));
      },
      onError: (error, stackTrace) {
        state = AsyncValue.error(error, stackTrace);
      },
    );

    ref.onDispose(() async {
      await _subscription?.cancel();
      _subscription = null;
    });

    _initialize();
    return state;
  }

  Future<void> _initialize() async {
    try {
      final messages = await _repository.loadInitialChatTranscript();
      state = AsyncValue.data(List<ChatMessage>.unmodifiable(messages));
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
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

    await _repository.appendChatMessage(userMessage);
    await _enqueueBotReply(trimmed);
  }

  Future<void> clearConversation() async {
    _replyToken++;
    await _repository.replaceChatTranscript(const []);
    await _repository.loadInitialChatTranscript(forceRefresh: true);
  }

  Future<void> _enqueueBotReply(String prompt) async {
    final placeholder = ChatMessage(
      id: 'bot-placeholder-${DateTime.now().millisecondsSinceEpoch}',
      text: 'Thinking...',
      sender: ChatSender.bot,
      timestamp: DateTime.now(),
      isProcessing: true,
    );
    state = state.whenData((messages) {
      return List<ChatMessage>.unmodifiable([...messages, placeholder]);
    });

    final currentToken = ++_replyToken;
    final reply = await _repository.generateBotReply(prompt);
    if (currentToken != _replyToken) {
      return;
    }

    state = state.whenData((messages) {
      return List<ChatMessage>.unmodifiable([
        for (final message in messages)
          if (message.id == placeholder.id) reply else message,
      ]);
    });
  }
}

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);
