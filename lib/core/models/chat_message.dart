import 'package:equatable/equatable.dart';

enum ChatSender { bot, user }

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.sender,
    required this.timestamp,
    this.isProcessing = false,
    this.imageUrl,
    this.localImagePath,
    this.feedbackType,
    this.isFlagged = false,
    this.flagReason,
  });

  final String id;
  final String text;
  final ChatSender sender;
  final DateTime timestamp;
  final bool isProcessing;
  final String? imageUrl; // Remote URL from Supabase Storage
  final String? localImagePath; // Local file path before upload
  final String? feedbackType; // 'thumbs_up', 'thumbs_down', or null
  final bool isFlagged;
  final String? flagReason; // Reason provided by user when flagging

  ChatMessage copyWith({
    String? id,
    String? text,
    ChatSender? sender,
    DateTime? timestamp,
    bool? isProcessing,
    String? imageUrl,
    String? localImagePath,
    String? feedbackType,
    bool? isFlagged,
    String? flagReason,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      sender: sender ?? this.sender,
      timestamp: timestamp ?? this.timestamp,
      isProcessing: isProcessing ?? this.isProcessing,
      imageUrl: imageUrl ?? this.imageUrl,
      localImagePath: localImagePath ?? this.localImagePath,
      feedbackType: feedbackType ?? this.feedbackType,
      isFlagged: isFlagged ?? this.isFlagged,
      flagReason: flagReason ?? this.flagReason,
    );
  }

  bool get isBot => sender == ChatSender.bot;
  bool get isUser => sender == ChatSender.user;
  bool get hasImage => imageUrl != null || localImagePath != null;

  @override
  List<Object?> get props => [
        id,
        text,
        sender,
        timestamp,
        isProcessing,
        imageUrl,
        localImagePath,
        feedbackType,
        isFlagged,
        flagReason,
      ];
}
