import 'package:equatable/equatable.dart';

import 'study_content_type.dart';

class StudyPlanTask extends Equatable {
  const StudyPlanTask({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.contentType,
    required this.isCompleted,
  });

  final String id;
  final String title;
  final DateTime dueDate;
  final StudyContentType contentType;
  final bool isCompleted;

  StudyPlanTask copyWith({
    String? id,
    String? title,
    DateTime? dueDate,
    StudyContentType? contentType,
    bool? isCompleted,
  }) {
    return StudyPlanTask(
      id: id ?? this.id,
      title: title ?? this.title,
      dueDate: dueDate ?? this.dueDate,
      contentType: contentType ?? this.contentType,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  @override
  List<Object?> get props => [id, title, dueDate, contentType, isCompleted];
}
