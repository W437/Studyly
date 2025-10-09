import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/navigation/routes.dart';
import '../../../core/providers/scan_providers.dart';
import '../../../ui/theme/color_tokens.dart';

class CustomCameraScreen extends ConsumerStatefulWidget {
  const CustomCameraScreen({super.key});

  @override
  ConsumerState<CustomCameraScreen> createState() => _CustomCameraScreenState();
}

class _CustomCameraScreenState extends ConsumerState<CustomCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isFlashOn = false;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        return;
      }

      final camera = cameras.first;
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitialized = true;
      });
    } catch (e) {
      // Handle error
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;

    try {
      setState(() {
        _isFlashOn = !_isFlashOn;
      });

      await _controller!.setFlashMode(
        _isFlashOn ? FlashMode.torch : FlashMode.off,
      );
    } catch (e) {
      debugPrint('Error toggling flash: $e');
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    try {
      // Set flash mode for capture
      if (_isFlashOn) {
        await _controller!.setFlashMode(FlashMode.always);
      } else {
        await _controller!.setFlashMode(FlashMode.off);
      }

      final image = await _controller!.takePicture();
      final imageFile = File(image.path);

      if (!mounted) return;

      // Save the captured image using scan service
      final scanService = ref.read(scanServiceProvider);
      final savedFile = await scanService.saveCapturedImage(imageFile);

      // Create scanned item
      final scanController = ref.read(scanControllerProvider.notifier);
      final item = await scanController.createFromFile(savedFile);

      if (item != null && mounted) {
        context.go(AppRoute.scanPreview.path.replaceAll(':id', item.id));
      }
    } catch (e) {
      debugPrint('Error taking picture: $e');
    }
  }

  Future<void> _openGallery() async {
    try {
      final images = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (images.isEmpty || !mounted) return;

      // Limit to 10 images
      final limitedImages = images.take(10).toList();

      if (limitedImages.length == 1) {
        // Single image - use existing flow
        final scanController = ref.read(scanControllerProvider.notifier);
        final item = await scanController.pickFromGallery();

        if (item != null && mounted) {
          context.go(AppRoute.scanPreview.path.replaceAll(':id', item.id));
        }
      } else {
        // Multiple images - show a message for now
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Selected ${limitedImages.length} images'),
              duration: const Duration(seconds: 2),
            ),
          );
          // TODO: Implement batch processing
        }
      }
    } catch (e) {
      debugPrint('Error opening gallery: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera Preview
          if (_isInitialized && _controller != null)
            CameraPreview(_controller!)
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          // Scan area overlay
          if (_isInitialized)
            CustomPaint(
              painter: ScanOverlayPainter(),
              child: Container(),
            ),

          // Top bar with close button
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Flash button
                    _ControlButton(
                      onPressed: _toggleFlash,
                      child: Icon(
                        _isFlashOn ? Icons.flash_on : Icons.flash_off,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),

                    // Capture button
                    GestureDetector(
                      onTap: _takePicture,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                            color: Colors.white,
                            width: 4,
                          ),
                        ),
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: StudyColors.primary,
                          ),
                        ),
                      ),
                    ),

                    // Gallery button
                    _ControlButton(
                      onPressed: _openGallery,
                      child: const Icon(
                        Icons.photo_library,
                        color: Colors.white,
                        size: 28,
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

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.onPressed,
    required this.child,
  });

  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.shade800.withOpacity(0.6),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: child,
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    // Draw semi-transparent overlay for the entire screen
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Calculate scan area (centered rectangle)
    final scanWidth = size.width * 0.8;
    final scanHeight = size.height * 0.5;
    final scanLeft = (size.width - scanWidth) / 2;
    final scanTop = (size.height - scanHeight) / 2;

    // Clear the scan area
    final clearPaint = Paint()
      ..color = Colors.transparent
      ..blendMode = BlendMode.clear;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(scanLeft, scanTop, scanWidth, scanHeight),
        const Radius.circular(16),
      ),
      clearPaint,
    );

    // Draw border for scan area
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(scanLeft, scanTop, scanWidth, scanHeight),
        const Radius.circular(16),
      ),
      borderPaint,
    );

    // Draw corner decorations
    final cornerLength = 30.0;
    final cornerPaint = Paint()
      ..color = StudyColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    // Top-left corner
    canvas.drawLine(
      Offset(scanLeft, scanTop + cornerLength),
      Offset(scanLeft, scanTop),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanLeft, scanTop),
      Offset(scanLeft + cornerLength, scanTop),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(scanLeft + scanWidth - cornerLength, scanTop),
      Offset(scanLeft + scanWidth, scanTop),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanLeft + scanWidth, scanTop),
      Offset(scanLeft + scanWidth, scanTop + cornerLength),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(scanLeft, scanTop + scanHeight - cornerLength),
      Offset(scanLeft, scanTop + scanHeight),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanLeft, scanTop + scanHeight),
      Offset(scanLeft + cornerLength, scanTop + scanHeight),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(scanLeft + scanWidth - cornerLength, scanTop + scanHeight),
      Offset(scanLeft + scanWidth, scanTop + scanHeight),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanLeft + scanWidth, scanTop + scanHeight - cornerLength),
      Offset(scanLeft + scanWidth, scanTop + scanHeight),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
