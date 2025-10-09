import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/routes.dart';
import '../../../ui/theme/color_tokens.dart';
import '../application/chat_controller.dart';
import 'chat_screen.dart';

class ChatScreenWrapper extends ConsumerWidget {
  const ChatScreenWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(chatControllerProvider.notifier);

    return Scaffold(
      backgroundColor: StudyColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go(AppRoute.home.path),
        ),
        centerTitle: true,
        title: const Text(
          'Chat with StudyBot',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.black87),
            onSelected: (value) {
              if (value == 'clear') {
                controller.clearConversation();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'search',
                child: Row(
                  children: [
                    Icon(Icons.search, color: Colors.black87),
                    SizedBox(width: 12),
                    Text('Search'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.file_upload_outlined, color: Colors.black87),
                    SizedBox(width: 12),
                    Text('Export Chat'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Colors.redAccent),
                    SizedBox(width: 12),
                    Text(
                      'Clear Chat',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: const ChatScreen(),
    );
  }
}
