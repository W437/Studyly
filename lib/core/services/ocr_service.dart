import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRResult {
  const OCRResult({
    required this.text,
    required this.blocks,
    required this.confidence,
  });

  final String text;
  final List<TextBlock> blocks;
  final double confidence;
}

class OCRService {
  OCRService() : _textRecognizer = TextRecognizer();

  final TextRecognizer _textRecognizer;

  /// Extract text from image using Google ML Kit
  Future<OCRResult> extractText(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      if (recognizedText.text.isEmpty) {
        throw Exception('No text found in image');
      }

      // Calculate average confidence if available
      double totalConfidence = 0;
      int blockCount = 0;

      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          // Note: ML Kit doesn't provide confidence scores in all versions
          // This is a placeholder for when/if they do
          totalConfidence += 1.0;
          blockCount++;
        }
      }

      final averageConfidence = blockCount > 0 ? totalConfidence / blockCount : 1.0;

      return OCRResult(
        text: recognizedText.text,
        blocks: recognizedText.blocks,
        confidence: averageConfidence,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Extract text with progress callback
  Future<OCRResult> extractTextWithProgress(
    File imageFile,
    void Function(double progress) onProgress,
  ) async {
    try {
      onProgress(0.1);

      final inputImage = InputImage.fromFile(imageFile);
      onProgress(0.3);

      final recognizedText = await _textRecognizer.processImage(inputImage);
      onProgress(0.9);

      if (recognizedText.text.isEmpty) {
        throw Exception('No text found in image');
      }

      double totalConfidence = 0;
      int blockCount = 0;

      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          totalConfidence += 1.0;
          blockCount++;
        }
      }

      final averageConfidence = blockCount > 0 ? totalConfidence / blockCount : 1.0;

      onProgress(1.0);

      return OCRResult(
        text: recognizedText.text,
        blocks: recognizedText.blocks,
        confidence: averageConfidence,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Close the recognizer when done
  Future<void> dispose() async {
    await _textRecognizer.close();
  }
}
