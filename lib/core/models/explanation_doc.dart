import 'package:equatable/equatable.dart';

class ExplanationDoc extends Equatable {
  const ExplanationDoc({
    required this.id,
    required this.studySetId,
    required this.title,
    required this.summary,
    required this.content,
    required this.createdAt,
    this.keyPoints = const [],
    this.sourceImageUrl,
  });

  final String id;
  final String studySetId;
  final String title;
  final String summary;
  final List<String> keyPoints;
  final String content; // Markdown formatted content
  final String? sourceImageUrl;
  final DateTime createdAt;

  ExplanationDoc copyWith({
    String? id,
    String? studySetId,
    String? title,
    String? summary,
    List<String>? keyPoints,
    String? content,
    String? sourceImageUrl,
    DateTime? createdAt,
  }) {
    return ExplanationDoc(
      id: id ?? this.id,
      studySetId: studySetId ?? this.studySetId,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      keyPoints: keyPoints ?? this.keyPoints,
      content: content ?? this.content,
      sourceImageUrl: sourceImageUrl ?? this.sourceImageUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        studySetId,
        title,
        summary,
        keyPoints,
        content,
        sourceImageUrl,
        createdAt,
      ];
}
