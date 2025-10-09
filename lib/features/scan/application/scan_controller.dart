import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/scanned_item.dart';
import '../../../core/services/ocr_service.dart';
import '../../../core/services/scan_service.dart';
import '../../../core/data/data_sources/study_local_data_source.dart';

class ScanState {
  const ScanState({
    this.currentItem,
    this.isLoading = false,
    this.error,
    this.ocrProgress = 0.0,
  });

  final ScannedItem? currentItem;
  final bool isLoading;
  final String? error;
  final double ocrProgress;

  ScanState copyWith({
    ScannedItem? currentItem,
    bool? isLoading,
    String? error,
    double? ocrProgress,
  }) {
    return ScanState(
      currentItem: currentItem ?? this.currentItem,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      ocrProgress: ocrProgress ?? this.ocrProgress,
    );
  }
}

class ScanController extends StateNotifier<ScanState> {
  ScanController({
    required ScanService scanService,
    required OCRService ocrService,
    required StudyLocalDataSource localDataSource,
    required String userId,
  })  : _scanService = scanService,
        _ocrService = ocrService,
        _localDataSource = localDataSource,
        _userId = userId,
        super(const ScanState());

  final ScanService _scanService;
  final OCRService _ocrService;
  final StudyLocalDataSource _localDataSource;
  final String _userId;
  final _uuid = const Uuid();

  /// Take photo from camera
  Future<ScannedItem?> takePhoto() async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final imageFile = await _scanService.takePhoto();
      if (imageFile == null) {
        state = state.copyWith(isLoading: false);
        return null;
      }

      return await _createScannedItem(imageFile);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  /// Pick image from gallery
  Future<ScannedItem?> pickFromGallery() async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final imageFile = await _scanService.pickFromGallery();
      if (imageFile == null) {
        state = state.copyWith(isLoading: false);
        return null;
      }

      return await _createScannedItem(imageFile);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  /// Create a scanned item from an image file
  Future<ScannedItem> _createScannedItem(File imageFile) async {
    final item = ScannedItem(
      id: _uuid.v4(),
      userId: _userId,
      localImagePath: imageFile.path,
      status: ScanStatus.captured,
      createdAt: DateTime.now(),
    );

    await _localDataSource.saveScannedItem(item);
    state = state.copyWith(currentItem: item, isLoading: false);

    // Upload to Supabase in background
    _uploadImageInBackground(item);

    return item;
  }

  /// Upload image to Supabase Storage (background operation)
  Future<void> _uploadImageInBackground(ScannedItem item) async {
    try {
      final imageFile = File(item.localImagePath);
      final remoteUrl = await _scanService.uploadToSupabase(
        imageFile: imageFile,
        userId: _userId,
      );

      final updatedItem = item.copyWith(remoteImageUrl: remoteUrl);
      await _localDataSource.saveScannedItem(updatedItem);

      if (state.currentItem?.id == item.id) {
        state = state.copyWith(currentItem: updatedItem);
      }
    } catch (e) {
      // Ignore upload errors - we have local copy
    }
  }

  /// Run OCR on scanned item
  Future<void> runOCR(String itemId) async {
    try {
      state = state.copyWith(isLoading: true, error: null, ocrProgress: 0.0);

      final item = await _localDataSource.loadScannedItem(itemId);
      if (item == null) {
        throw Exception('Scanned item not found');
      }

      // Update status to processing
      var updatedItem = item.copyWith(status: ScanStatus.processing);
      await _localDataSource.saveScannedItem(updatedItem);
      state = state.copyWith(currentItem: updatedItem);

      // Run OCR with progress
      final imageFile = File(item.localImagePath);
      final result = await _ocrService.extractTextWithProgress(
        imageFile,
        (progress) {
          state = state.copyWith(ocrProgress: progress);
        },
      );

      // Update with OCR result
      updatedItem = updatedItem.copyWith(
        ocrText: result.text,
        status: ScanStatus.ready,
      );
      await _localDataSource.saveScannedItem(updatedItem);

      state = state.copyWith(
        currentItem: updatedItem,
        isLoading: false,
        ocrProgress: 1.0,
      );
    } catch (e) {
      final item = state.currentItem;
      if (item != null) {
        final errorItem = item.copyWith(
          status: ScanStatus.error,
          errorMessage: e.toString(),
        );
        await _localDataSource.saveScannedItem(errorItem);
        state = state.copyWith(currentItem: errorItem);
      }

      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Set selected action for scanned item
  Future<void> selectAction(String itemId, String action) async {
    try {
      final item = await _localDataSource.loadScannedItem(itemId);
      if (item == null) {
        throw Exception('Scanned item not found');
      }

      final updatedItem = item.copyWith(
        selectedAction: action,
        status: ScanStatus.actionSelected,
      );
      await _localDataSource.saveScannedItem(updatedItem);

      state = state.copyWith(currentItem: updatedItem);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Mark scanned item as completed
  Future<void> markCompleted(String itemId) async {
    try {
      final item = await _localDataSource.loadScannedItem(itemId);
      if (item == null) {
        throw Exception('Scanned item not found');
      }

      final updatedItem = item.copyWith(status: ScanStatus.completed);
      await _localDataSource.saveScannedItem(updatedItem);

      state = state.copyWith(currentItem: updatedItem);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Delete scanned item
  Future<void> deleteScannedItem(String itemId) async {
    try {
      final item = await _localDataSource.loadScannedItem(itemId);
      if (item != null) {
        // Delete local file
        await _scanService.deleteLocalFile(item.localImagePath);
      }

      await _localDataSource.deleteScannedItem(itemId);

      if (state.currentItem?.id == itemId) {
        state = const ScanState();
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Load scanned item by ID
  Future<void> loadScannedItem(String itemId) async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final item = await _localDataSource.loadScannedItem(itemId);
      state = state.copyWith(currentItem: item, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Clear current state
  void clear() {
    state = const ScanState();
  }
}
