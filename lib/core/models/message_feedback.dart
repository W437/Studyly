import 'package:equatable/equatable.dart';

enum FeedbackType { thumbsUp, thumbsDown, flag }

class MessageFeedback extends Equatable {
  const MessageFeedback({
    required this.id,
    required this.messageId,
    required this.type,
    required this.timestamp,
    this.comment,
  });

  final String id;
  final String messageId; // The chat message this feedback is for
  final FeedbackType type;
  final DateTime timestamp;
  final String? comment; // Optional comment for flags

  MessageFeedback copyWith({
    String? id,
    String? messageId,
    FeedbackType? type,
    DateTime? timestamp,
    String? comment,
  }) {
    return MessageFeedback(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      comment: comment ?? this.comment,
    );
  }

  @override
  List<Object?> get props => [id, messageId, type, timestamp, comment];
}
