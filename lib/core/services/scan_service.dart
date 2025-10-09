import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ScanService {
  ScanService({
    required ImagePicker imagePicker,
    required SupabaseClient supabaseClient,
  })  : _imagePicker = imagePicker,
        _supabase = supabaseClient;

  final ImagePicker _imagePicker;
  final SupabaseClient _supabase;
  final _uuid = const Uuid();

  /// Request camera permission
  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Request photo library permission
  Future<bool> requestPhotoLibraryPermission() async {
    final status = await Permission.photos.request();
    return status.isGranted || status.isLimited;
  }

  /// Capture image from camera
  Future<File?> takePhoto() async {
    try {
      final hasPermission = await requestCameraPermission();
      if (!hasPermission) {
        throw Exception('Camera permission denied');
      }

      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (photo == null) {
        return null;
      }

      // Save to permanent storage
      return await _saveToPermanentStorage(File(photo.path));
    } catch (e) {
      rethrow;
    }
  }

  /// Pick image from gallery
  Future<File?> pickFromGallery() async {
    try {
      final hasPermission = await requestPhotoLibraryPermission();
      if (!hasPermission) {
        throw Exception('Photo library permission denied');
      }

      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) {
        return null;
      }

      // Save to permanent storage
      return await _saveToPermanentStorage(File(image.path));
    } catch (e) {
      rethrow;
    }
  }

  /// Save file to app's permanent storage
  Future<File> _saveToPermanentStorage(File tempFile) async {
    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${directory.path}/scans');

    if (!await scansDir.exists()) {
      await scansDir.create(recursive: true);
    }

    final fileName = '${_uuid.v4()}.jpg';
    final permanentPath = '${scansDir.path}/$fileName';

    return await tempFile.copy(permanentPath);
  }

  /// Save captured image from custom camera
  Future<File> saveCapturedImage(File imageFile) async {
    return await _saveToPermanentStorage(imageFile);
  }

  /// Upload image to Supabase Storage
  Future<String> uploadToSupabase({
    required File imageFile,
    required String userId,
  }) async {
    try {
      final fileName = '${_uuid.v4()}.jpg';
      final path = '$userId/${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}/$fileName';

      await _supabase.storage
          .from('scans')
          .upload(
            path,
            imageFile,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
            ),
          );

      // Get signed URL (valid for 1 year)
      final signedUrl = await _supabase.storage
          .from('scans')
          .createSignedUrl(path, 31536000);

      return signedUrl;
    } catch (e) {
      rethrow;
    }
  }

  /// Delete local scan file
  Future<void> deleteLocalFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Ignore deletion errors
    }
  }
}
