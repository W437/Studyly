import 'package:equatable/equatable.dart';

enum ScanStatus {
  captured, // Image captured/imported
  processing, // OCR in progress
  ready, // OCR complete, ready for action selection
  actionSelected, // User chose an action
  completed, // Final action completed
  error // Error occurred
}

class ScannedItem extends Equatable {
  const ScannedItem({
    required this.id,
    required this.userId,
    required this.localImagePath,
    required this.status,
    required this.createdAt,
    this.remoteImageUrl,
    this.ocrText,
    this.selectedAction,
    this.errorMessage,
  });

  final String id;
  final String userId;
  final String localImagePath;
  final String? remoteImageUrl;
  final ScanStatus status;
  final String? ocrText;
  final String? selectedAction; // 'solve_chat', 'flashcards', 'explanation', 'exercise'
  final String? errorMessage;
  final DateTime createdAt;

  ScannedItem copyWith({
    String? id,
    String? userId,
    String? localImagePath,
    String? remoteImageUrl,
    ScanStatus? status,
    String? ocrText,
    String? selectedAction,
    String? errorMessage,
    DateTime? createdAt,
  }) {
    return ScannedItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      localImagePath: localImagePath ?? this.localImagePath,
      remoteImageUrl: remoteImageUrl ?? this.remoteImageUrl,
      status: status ?? this.status,
      ocrText: ocrText ?? this.ocrText,
      selectedAction: selectedAction ?? this.selectedAction,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        localImagePath,
        remoteImageUrl,
        status,
        ocrText,
        selectedAction,
        errorMessage,
        createdAt,
      ];
}
