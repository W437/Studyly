import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';

import '../../../app/navigation/routes.dart';
import '../../../core/providers/scan_providers.dart';

class ScanPreviewScreen extends ConsumerStatefulWidget {
  const ScanPreviewScreen({
    required this.scannedItemId,
    super.key,
  });

  final String scannedItemId;

  @override
  ConsumerState<ScanPreviewScreen> createState() => _ScanPreviewScreenState();
}

class _ScanPreviewScreenState extends ConsumerState<ScanPreviewScreen> {
  int _rotationAngle = 0;

  @override
  void initState() {
    super.initState();
    // Load the scanned item when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScannedItem();
    });
  }

  Future<void> _loadScannedItem() async {
    await ref
        .read(scanControllerProvider.notifier)
        .loadScannedItem(widget.scannedItemId);
  }

  Future<void> _cropImage() async {
    final currentItem = ref.read(scanControllerProvider).currentItem;
    if (currentItem == null) return;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: currentItem.localImagePath,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Image',
          toolbarColor: Theme.of(context).primaryColor,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          hideBottomControls: false,
          statusBarColor: Theme.of(context).primaryColor,
          activeControlsWidgetColor: Theme.of(context).primaryColor,
        ),
        IOSUiSettings(
          title: 'Crop Image',
          aspectRatioPickerButtonHidden: false,
          resetButtonHidden: false,
          rotateButtonsHidden: false,
        ),
      ],
    );

    if (croppedFile != null) {
      // Update the scanned item with new cropped image path
      final updatedItem = currentItem.copyWith(
        localImagePath: croppedFile.path,
      );
      await ref.read(scanControllerProvider.notifier).updateCurrentItem(updatedItem);
    }
  }

  Future<void> _rotateImage() async {
    setState(() {
      _rotationAngle = (_rotationAngle + 90) % 360;
    });
  }

  Future<void> _retake() async {
    // Delete current item and navigate back to camera
    await ref
        .read(scanControllerProvider.notifier)
        .deleteScannedItem(widget.scannedItemId);

    if (mounted) {
      // Pop twice to get back to the screen before camera, then camera will open again
      // Or navigate directly to camera route
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _continue() {
    context.push(
      AppRoute.scanOcr.path.replaceAll(':id', widget.scannedItemId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(scanControllerProvider);
    final currentItem = scanState.currentItem;

    if (scanState.isLoading || currentItem == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Preview'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview Image'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () async {
            // Delete the item and go back to where we came from
            await ref
                .read(scanControllerProvider.notifier)
                .deleteScannedItem(widget.scannedItemId);
            if (mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          },
        ),
        actions: [
          TextButton.icon(
            onPressed: _retake,
            icon: const Icon(Icons.refresh),
            label: const Text('Retake'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Image Preview
          Expanded(
            child: Container(
              color: Colors.black,
              child: Center(
                child: RotatedBox(
                  quarterTurns: _rotationAngle ~/ 90,
                  child: Image.file(
                    File(currentItem.localImagePath),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),

          // Controls
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Crop Button
                    _ActionButton(
                      icon: Icons.crop,
                      label: 'Crop',
                      onPressed: _cropImage,
                    ),

                    // Rotate Button
                    _ActionButton(
                      icon: Icons.rotate_right,
                      label: 'Rotate',
                      onPressed: _rotateImage,
                    ),

                    // Continue Button
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: ElevatedButton(
                          onPressed: _continue,
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
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
