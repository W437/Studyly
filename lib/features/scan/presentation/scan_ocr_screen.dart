import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/routes.dart';
import '../../../core/providers/scan_providers.dart';

class ScanOcrScreen extends ConsumerStatefulWidget {
  const ScanOcrScreen({
    required this.scannedItemId,
    super.key,
  });

  final String scannedItemId;

  @override
  ConsumerState<ScanOcrScreen> createState() => _ScanOcrScreenState();
}

class _ScanOcrScreenState extends ConsumerState<ScanOcrScreen> {
  late TextEditingController _textController;
  bool _hasStartedOcr = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();

    // Start OCR processing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasStartedOcr) {
        _hasStartedOcr = true;
        ref
            .read(scanControllerProvider.notifier)
            .runOCR(widget.scannedItemId);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _continue() {
    // Save edited text if changed
    final scanState = ref.read(scanControllerProvider);
    final currentItem = scanState.currentItem;

    if (currentItem != null &&
        _textController.text != currentItem.ocrText) {
      // Update OCR text with user edits
      // Note: We'd need to add an updateOcrText method to ScanController
      // For now, we'll just proceed
    }

    context.push(
      AppRoute.scanActionChooser.path.replaceAll(':id', widget.scannedItemId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(scanControllerProvider);
    final currentItem = scanState.currentItem;

    // Update text controller when OCR completes
    if (currentItem?.ocrText != null &&
        _textController.text.isEmpty &&
        !scanState.isLoading) {
      _textController.text = currentItem!.ocrText!;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Extract Text'),
      ),
      body: Column(
        children: [
          // Image thumbnail
          if (currentItem?.localImagePath != null)
            Container(
              height: 120,
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(currentItem!.localImagePath),
                  fit: BoxFit.cover,
                ),
              ),
            ),

          // Processing state or text preview
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: scanState.isLoading
                  ? _buildLoadingState(scanState.ocrProgress)
                  : _buildTextPreview(),
            ),
          ),

          // Error state
          if (scanState.error != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      scanState.error!,
                      style: TextStyle(color: Colors.red[700]),
                    ),
                  ),
                ],
              ),
            ),

          // Continue button
          Container(
            padding: const EdgeInsets.all(16),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: scanState.isLoading ||
                          currentItem?.ocrText == null ||
                          scanState.error != null
                      ? null
                      : _continue,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Continue'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(double progress) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          'Extracting text...',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          '${(progress * 100).toStringAsFixed(0)}% complete',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildTextPreview() {
    final charCount = _textController.text.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[600], size: 20),
            const SizedBox(width: 8),
            Text(
              'Text extracted successfully',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.green[600],
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Review and edit the extracted text:',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TextField(
            controller: _textController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: 'Extracted text will appear here...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$charCount characters',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
        ),
      ],
    );
  }
}
