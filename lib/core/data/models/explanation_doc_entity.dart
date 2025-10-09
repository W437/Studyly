import 'package:isar/isar.dart';

part 'explanation_doc_entity.g.dart';

@collection
class ExplanationDocEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String docId;

  late String studySetId;
  late String title;
  late String summary;
  late List<String> keyPoints;
  late String content;
  String? sourceImageUrl;
  late DateTime createdAt;

  ExplanationDocEntity();

  ExplanationDocEntity.create({
    required this.docId,
    required this.studySetId,
    required this.title,
    required this.summary,
    required this.keyPoints,
    required this.content,
    this.sourceImageUrl,
    required this.createdAt,
  });
}
