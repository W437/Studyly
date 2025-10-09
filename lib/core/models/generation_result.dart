import 'package:equatable/equatable.dart';

enum GenerationStatus { pending, processing, completed, failed }

enum GenerationType { flashcards, explanation, exercise, chatSolve }

class GenerationResult extends Equatable {
  const GenerationResult({
    required this.id,
    required this.userId,
    required this.scannedItemId,
    required this.type,
    required this.status,
    required this.createdAt,
    this.inputText,
    this.imageUrl,
    this.result,
    this.errorMessage,
    this.completedAt,
  });

  final String id;
  final String userId;
  final String scannedItemId;
  final GenerationType type;
  final GenerationStatus status;
  final String? inputText;
  final String? imageUrl;
  final Map<String, dynamic>? result; // JSON result from AI
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? completedAt;

  GenerationResult copyWith({
    String? id,
    String? userId,
    String? scannedItemId,
    GenerationType? type,
    GenerationStatus? status,
    String? inputText,
    String? imageUrl,
    Map<String, dynamic>? result,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return GenerationResult(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      scannedItemId: scannedItemId ?? this.scannedItemId,
      type: type ?? this.type,
      status: status ?? this.status,
      inputText: inputText ?? this.inputText,
      imageUrl: imageUrl ?? this.imageUrl,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        scannedItemId,
        type,
        status,
        inputText,
        imageUrl,
        result,
        errorMessage,
        createdAt,
        completedAt,
      ];
}
