import 'package:isar/isar.dart';

part 'scanned_item_entity.g.dart';

@collection
class ScannedItemEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String itemId;

  late String userId;
  late String localImagePath;
  String? remoteImageUrl;
  late int statusIndex; // Maps to ScanStatus enum
  String? ocrText;
  String? selectedAction;
  String? errorMessage;
  late DateTime createdAt;

  ScannedItemEntity();

  ScannedItemEntity.create({
    required this.itemId,
    required this.userId,
    required this.localImagePath,
    this.remoteImageUrl,
    required this.statusIndex,
    this.ocrText,
    this.selectedAction,
    this.errorMessage,
    required this.createdAt,
  });
}
