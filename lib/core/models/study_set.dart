import 'package:equatable/equatable.dart';

import 'study_content_type.dart';

class StudySet extends Equatable {
  const StudySet({
    required this.id,
    required this.title,
    required this.flashcards,
    required this.explanations,
    required this.exercises,
    required this.views,
    required this.borderColor,
    required this.tag,
    required this.description,
  });

  final String id;
  final String title;
  final int flashcards;
  final int explanations;
  final int exercises;
  final String views;
  final int borderColor;
  final StudyMaterialTag tag;
  final String description;

  int get totalItems => flashcards + explanations + exercises;

  StudySet copyWith({
    String? id,
    String? title,
    int? flashcards,
    int? explanations,
    int? exercises,
    String? views,
    int? borderColor,
    StudyMaterialTag? tag,
    String? description,
  }) {
    return StudySet(
      id: id ?? this.id,
      title: title ?? this.title,
      flashcards: flashcards ?? this.flashcards,
      explanations: explanations ?? this.explanations,
      exercises: exercises ?? this.exercises,
      views: views ?? this.views,
      borderColor: borderColor ?? this.borderColor,
      tag: tag ?? this.tag,
      description: description ?? this.description,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    flashcards,
    explanations,
    exercises,
    views,
    borderColor,
    tag,
    description,
  ];
}
