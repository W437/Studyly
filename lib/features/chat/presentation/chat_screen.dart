import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/chat_message.dart';
import '../../../ui/theme/color_tokens.dart';
import '../application/chat_controller.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  late final ScrollController _scrollController;
  final ImagePicker _imagePicker = ImagePicker();
  String? _selectedImagePath;
  final Set<String> _animatedMessageIds = {};

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  void _sendMessage() {
    final text = _messageController.text;
    if (text.trim().isEmpty && _selectedImagePath == null) return;

    ref.read(chatControllerProvider.notifier).sendUserMessage(
          text,
          localImagePath: _selectedImagePath,
        );
    _messageController.clear();
    setState(() {
      _selectedImagePath = null;
    });
  }

  Future<void> _pickImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImagePath = image.path;
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImagePath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider);

    ref.listen<ChatState>(chatControllerProvider, (previous, next) {
      if (!next.hasValue) {
        return;
      }
      if (_scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });

    return Column(
      children: [
        Expanded(
          child: chatState.when(
            data: (value) => ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: value.length,
              itemBuilder: (context, index) {
                final message = value[index];
                final shouldAnimate = !_animatedMessageIds.contains(message.id);
                if (shouldAnimate) {
                  _animatedMessageIds.add(message.id);
                }
                return _AnimatedMessageBubble(
                  key: ValueKey(message.id),
                  message: message,
                  index: index,
                  shouldAnimate: shouldAnimate,
                );
              },
            ),
            loading: () => const Center(
              child: CircularProgressIndicator(),
            ),
            error: (error, stackTrace) => Center(
              child: Text('Something went wrong: ${error.toString()}'),
            ),
          ),
        ),
        Container(
          color: Colors.white,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Image preview
                if (_selectedImagePath != null)
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(_selectedImagePath!),
                            height: 120,
                            width: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: _removeImage,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _messageController,
                                  decoration: const InputDecoration(
                                    hintText:
                                        'Ask me anything about your study plan...',
                                    hintStyle: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 15,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                  ),
                                  onSubmitted: (_) => _sendMessage(),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  _selectedImagePath != null
                                      ? Icons.image
                                      : Icons.attach_file,
                                  color: _selectedImagePath != null
                                      ? StudyColors.primary
                                      : Colors.black54,
                                  size: 22,
                                ),
                                onPressed: _pickImage,
                              ),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: StudyColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.send,
                              color: Colors.white, size: 22),
                          onPressed: _sendMessage,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _AnimatedMessageBubble extends StatefulWidget {
  const _AnimatedMessageBubble({
    super.key,
    required this.message,
    required this.index,
    required this.shouldAnimate,
  });

  final ChatMessage message;
  final int index;
  final bool shouldAnimate;

  @override
  State<_AnimatedMessageBubble> createState() => _AnimatedMessageBubbleState();
}

class _AnimatedMessageBubbleState extends State<_AnimatedMessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    // Only animate if this is a new message
    if (widget.shouldAnimate) {
      // Start animation after a tiny delay for staggered effect
      Future.delayed(Duration(milliseconds: widget.index * 30), () {
        if (mounted) {
          _controller.forward();
        }
      });
    } else {
      // Skip animation for existing messages
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        alignment: widget.message.isBot
            ? Alignment.centerLeft
            : Alignment.centerRight,
        child: _MessageBubble(message: widget.message),
      ),
    );
  }
}

class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  Future<void> _showFlagDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report Message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Why are you reporting this message?'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter your reason here...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Report'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await ref
          .read(chatControllerProvider.notifier)
          .flagMessage(message.id, result);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message reported. Thank you for your feedback.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: message.isBot
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: message.isBot ? Colors.white : StudyColors.primary,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.isProcessing)
                  const _TypingIndicator()
                else ...[
                  // Display image if present
                  if (message.hasImage) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: message.imageUrl != null
                          ? Image.network(
                              message.imageUrl!,
                              fit: BoxFit.cover,
                              width: 200,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 200,
                                  height: 150,
                                  color: Colors.grey.shade200,
                                  child: const Icon(
                                    Icons.broken_image,
                                    color: Colors.grey,
                                    size: 48,
                                  ),
                                );
                              },
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Container(
                                  width: 200,
                                  height: 150,
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              },
                            )
                          : message.localImagePath != null
                              ? Image.file(
                                  File(message.localImagePath!),
                                  fit: BoxFit.cover,
                                  width: 200,
                                )
                              : const SizedBox.shrink(),
                    ),
                    if (message.text.isNotEmpty) const SizedBox(height: 8),
                  ],
                  // Display text if present
                  if (message.text.isNotEmpty)
                    Text(
                      message.text,
                      style: TextStyle(
                        color: message.isBot ? Colors.black87 : Colors.white,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                ],
                if (message.isBot && !message.isProcessing) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ActionIcon(
                        message.feedbackType == 'thumbs_up'
                            ? Icons.thumb_up
                            : Icons.thumb_up_outlined,
                        color: message.feedbackType == 'thumbs_up'
                            ? StudyColors.primary
                            : Colors.black54,
                        onPressed: () => ref
                            .read(chatControllerProvider.notifier)
                            .setMessageFeedback(message.id, 'thumbs_up'),
                      ),
                      const SizedBox(width: 16),
                      _ActionIcon(
                        message.feedbackType == 'thumbs_down'
                            ? Icons.thumb_down
                            : Icons.thumb_down_outlined,
                        color: message.feedbackType == 'thumbs_down'
                            ? StudyColors.primary
                            : Colors.black54,
                        onPressed: () => ref
                            .read(chatControllerProvider.notifier)
                            .setMessageFeedback(message.id, 'thumbs_down'),
                      ),
                      const SizedBox(width: 16),
                      _ActionIcon(
                        Icons.copy_outlined,
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: message.text));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied to clipboard'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 16),
                      _ActionIcon(
                        Icons.share_outlined,
                        onPressed: () {
                          Share.share(message.text);
                        },
                      ),
                      const SizedBox(width: 16),
                      _ActionIcon(
                        message.isFlagged ? Icons.flag : Icons.flag_outlined,
                        color: message.isFlagged ? Colors.red : Colors.black54,
                        onPressed: () => _showFlagDialog(context, ref),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon(
    this.icon, {
    this.color = Colors.black54,
    this.onPressed,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final delay = index * 0.2;
            final value = (_controller.value - delay) % 1.0;
            final opacity = value < 0.5
                ? (value * 2)
                : (2 - value * 2);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity.clamp(0.3, 1.0),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: StudyColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
