import 'package:isar/isar.dart';

part 'chat_message_entity.g.dart';

@collection
class ChatMessageEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String messageId;

  late String text;
  late int senderIndex;
  late DateTime timestamp;
  String? imageUrl;
  String? localImagePath;
  String? feedbackType; // 'thumbs_up', 'thumbs_down', or null
  bool? isFlagged;
  String? flagReason; // Reason provided by user when flagging

  ChatMessageEntity();

  ChatMessageEntity.create({
    required this.messageId,
    required this.text,
    required this.senderIndex,
    required this.timestamp,
    this.imageUrl,
    this.localImagePath,
    this.feedbackType,
    this.isFlagged,
    this.flagReason,
  });
}
