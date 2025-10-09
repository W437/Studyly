import 'package:isar/isar.dart';

part 'generation_result_entity.g.dart';

@collection
class GenerationResultEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String resultId;

  late String userId;
  late String scannedItemId;
  late int typeIndex; // Maps to GenerationType enum
  late int statusIndex; // Maps to GenerationStatus enum
  String? inputText;
  String? imageUrl;
  String? resultJson; // JSON string of result
  String? errorMessage;
  late DateTime createdAt;
  DateTime? completedAt;

  GenerationResultEntity();

  GenerationResultEntity.create({
    required this.resultId,
    required this.userId,
    required this.scannedItemId,
    required this.typeIndex,
    required this.statusIndex,
    this.inputText,
    this.imageUrl,
    this.resultJson,
    this.errorMessage,
    required this.createdAt,
    this.completedAt,
  });
}
