import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/bootstrap.dart';
import '../data/data_sources/isar_study_local_data_source.dart';
import '../data/data_sources/study_local_data_source.dart';
import '../services/ai_generation_service.dart';
import '../services/ocr_service.dart';
import '../services/scan_service.dart';
import '../../features/scan/application/exercise_generation_controller.dart';
import '../../features/scan/application/explanation_generation_controller.dart';
import '../../features/scan/application/flashcard_generation_controller.dart';
import '../../features/scan/application/scan_controller.dart';

// ==================== Service Providers ====================

final scanServiceProvider = Provider<ScanService>((ref) {
  return ScanService(
    imagePicker: ImagePicker(),
    supabaseClient: Supabase.instance.client,
  );
});

final ocrServiceProvider = Provider<OCRService>((ref) {
  return OCRService();
});

final aiGenerationServiceProvider = Provider<AIGenerationService>((ref) {
  return AIGenerationService(
    supabaseClient: Supabase.instance.client,
  );
});

// ==================== Data Source Provider ====================

final localDataSourceProvider = Provider<StudyLocalDataSource>((ref) {
  final isar = ref.watch(isarProvider);
  return IsarStudyLocalDataSource(isar);
});

// ==================== Controller Providers ====================

final scanControllerProvider =
    StateNotifierProvider<ScanController, ScanState>((ref) {
  // Get user ID from Supabase auth
  final userId =
      Supabase.instance.client.auth.currentUser?.id ?? 'anonymous';

  return ScanController(
    scanService: ref.watch(scanServiceProvider),
    ocrService: ref.watch(ocrServiceProvider),
    localDataSource: ref.watch(localDataSourceProvider),
    userId: userId,
  );
});

final flashcardGenerationControllerProvider = StateNotifierProvider<
    FlashcardGenerationController, FlashcardGenerationState>((ref) {
  return FlashcardGenerationController(
    aiService: ref.watch(aiGenerationServiceProvider),
    localDataSource: ref.watch(localDataSourceProvider),
  );
});

final explanationGenerationControllerProvider = StateNotifierProvider<
    ExplanationGenerationController, ExplanationGenerationState>((ref) {
  return ExplanationGenerationController(
    aiService: ref.watch(aiGenerationServiceProvider),
    localDataSource: ref.watch(localDataSourceProvider),
  );
});

final exerciseGenerationControllerProvider = StateNotifierProvider<
    ExerciseGenerationController, ExerciseGenerationState>((ref) {
  return ExerciseGenerationController(
    aiService: ref.watch(aiGenerationServiceProvider),
    localDataSource: ref.watch(localDataSourceProvider),
  );
});
