import 'package:equatable/equatable.dart';

import 'study_content_type.dart';

class StudyDocument extends Equatable {
  const StudyDocument({
    required this.id,
    required this.title,
    required this.sizeLabel,
    required this.source,
    required this.category,
    required this.type,
  });

  final String id;
  final String title;
  final String sizeLabel;
  final String source;
  final StudyMaterialTag category;
  final StudyContentType type;

  @override
  List<Object?> get props => [id, title, sizeLabel, source, category, type];
}
