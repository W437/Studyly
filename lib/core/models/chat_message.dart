import 'package:equatable/equatable.dart';

enum ChatSender { bot, user }

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.sender,
    required this.timestamp,
    this.isProcessing = false,
  });

  final String id;
  final String text;
  final ChatSender sender;
  final DateTime timestamp;
  final bool isProcessing;

  ChatMessage copyWith({
    String? id,
    String? text,
    ChatSender? sender,
    DateTime? timestamp,
    bool? isProcessing,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      sender: sender ?? this.sender,
      timestamp: timestamp ?? this.timestamp,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }

  bool get isBot => sender == ChatSender.bot;
  bool get isUser => sender == ChatSender.user;

  @override
  List<Object?> get props => [id, text, sender, timestamp, isProcessing];
}
