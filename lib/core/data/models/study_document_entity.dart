import 'package:isar/isar.dart';

part 'study_document_entity.g.dart';

@collection
class StudyDocumentEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String documentId;

  late String title;
  late String sizeLabel;
  late String source;
  late int categoryIndex;
  late int typeIndex;

  StudyDocumentEntity();

  StudyDocumentEntity.create({
    required this.documentId,
    required this.title,
    required this.sizeLabel,
    required this.source,
    required this.categoryIndex,
    required this.typeIndex,
  });
}
