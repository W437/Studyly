import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/routes.dart';
import '../../../core/providers/scan_providers.dart';

class ScanCaptureScreen extends ConsumerWidget {
  const ScanCaptureScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanController = ref.read(scanControllerProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Title
            Text(
              'Scan Document',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Capture or import an image to get started',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 32),

            // Buttons Row
            Row(
              children: [
                // Take Photo Button
                Expanded(
                  child: _CaptureOptionButton(
                    icon: Icons.camera_alt,
                    title: 'Take Photo',
                    onTap: () async {
                      Navigator.pop(context);
                      final item = await scanController.takePhoto();
                      if (item != null && context.mounted) {
                        context.push(
                          AppRoute.scanPreview.path.replaceAll(':id', item.id),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),

                // Import from Gallery Button
                Expanded(
                  child: _CaptureOptionButton(
                    icon: Icons.photo_library,
                    title: 'Import from Gallery',
                    onTap: () async {
                      Navigator.pop(context);
                      final item = await scanController.pickFromGallery();
                      if (item != null && context.mounted) {
                        context.push(
                          AppRoute.scanPreview.path.replaceAll(':id', item.id),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _CaptureOptionButton extends StatelessWidget {
  const _CaptureOptionButton({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 32,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
