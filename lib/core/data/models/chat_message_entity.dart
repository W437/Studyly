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

  ChatMessageEntity();

  ChatMessageEntity.create({
    required this.messageId,
    required this.text,
    required this.senderIndex,
    required this.timestamp,
  });
}
