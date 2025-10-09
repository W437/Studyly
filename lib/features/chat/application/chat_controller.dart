import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/services/study_repository.dart';

typedef ChatState = AsyncValue<List<ChatMessage>>;

class ChatController extends Notifier<ChatState> {
  int _replyToken = 0;
  StreamSubscription<List<ChatMessage>>? _subscription;
  ChatMessage? _pendingBotMessage; // Track pending bot message

  StudyRepository get _repository => ref.read(studyRepositoryProvider);

  @override
  ChatState build() {
    state = const AsyncValue.loading();

    _subscription = _repository.watchChatTranscript().listen(
      (messages) {
        // If there's a pending bot message (typing indicator), append it
        final allMessages = _pendingBotMessage != null
            ? [...messages, _pendingBotMessage!]
            : messages;
        state = AsyncValue.data(List<ChatMessage>.unmodifiable(allMessages));
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

  Future<void> sendUserMessage(String text, {String? localImagePath}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && localImagePath == null) {
      return;
    }

    final userMessage = ChatMessage(
      id: 'user-${DateTime.now().millisecondsSinceEpoch}',
      text: trimmed,
      sender: ChatSender.user,
      timestamp: DateTime.now(),
      localImagePath: localImagePath,
    );

    await _repository.appendChatMessage(userMessage);
    await _enqueueBotReply(trimmed, localImagePath: localImagePath);
  }

  Future<void> clearConversation() async {
    _replyToken++;
    await _repository.replaceChatTranscript(const []);
    await _repository.loadInitialChatTranscript(forceRefresh: true);
  }

  Future<void> setMessageFeedback(String messageId, String feedbackType) async {
    final messages = await _repository.loadInitialChatTranscript();
    final message = messages.firstWhere((m) => m.id == messageId);

    final updatedMessage = message.copyWith(feedbackType: feedbackType);
    await _repository.updateChatMessage(updatedMessage);
  }

  Future<void> flagMessage(String messageId, String reason) async {
    final messages = await _repository.loadInitialChatTranscript();
    final message = messages.firstWhere((m) => m.id == messageId);

    final updatedMessage = message.copyWith(
      isFlagged: true,
      flagReason: reason,
    );
    await _repository.updateChatMessage(updatedMessage);
  }

  Future<void> _enqueueBotReply(String prompt, {String? localImagePath}) async {
    final currentToken = ++_replyToken;

    // Wait 1.1 seconds before showing typing indicator
    await Future.delayed(const Duration(milliseconds: 1100));

    // Check if this reply was cancelled
    if (currentToken != _replyToken) {
      return;
    }

    // Set pending bot message (typing indicator)
    _pendingBotMessage = ChatMessage(
      id: 'bot-placeholder-${DateTime.now().millisecondsSinceEpoch}',
      text: 'Thinking...',
      sender: ChatSender.bot,
      timestamp: DateTime.now(),
      isProcessing: true,
    );

    // Trigger state update to show typing indicator
    final currentMessages = await _repository.loadInitialChatTranscript();
    state = AsyncValue.data(
      List<ChatMessage>.unmodifiable([...currentMessages, _pendingBotMessage!]),
    );

    try {
      // Convert local image to base64 data URL for OpenAI Vision API
      String? imageDataUrl;
      if (localImagePath != null) {
        try {
          final file = File(localImagePath);
          final bytes = await file.readAsBytes();
          final base64Image = base64Encode(bytes);

          // Determine MIME type from file extension
          String mimeType = 'image/jpeg';
          if (localImagePath.toLowerCase().endsWith('.png')) {
            mimeType = 'image/png';
          } else if (localImagePath.toLowerCase().endsWith('.gif')) {
            mimeType = 'image/gif';
          } else if (localImagePath.toLowerCase().endsWith('.webp')) {
            mimeType = 'image/webp';
          }

          imageDataUrl = 'data:$mimeType;base64,$base64Image';
        } catch (e) {
          // If image conversion fails, continue without image
          debugPrint('Error converting image to base64: $e');
        }
      }

      final reply = await _repository.generateBotReply(prompt, imageUrl: imageDataUrl);

      if (currentToken != _replyToken) {
        return;
      }

      // Clear pending message and let the stream show the actual reply
      _pendingBotMessage = null;
    } catch (error) {
      // Clear pending message on error
      _pendingBotMessage = null;
      rethrow;
    }
  }
}

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);
