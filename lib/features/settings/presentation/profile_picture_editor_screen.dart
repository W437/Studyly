import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/profile_picture.dart';
import '../../../ui/theme/color_tokens.dart';
import '../../../ui/widgets/profile_picture_widget.dart';

class ProfilePictureEditorScreen extends StatefulWidget {
  const ProfilePictureEditorScreen({
    super.key,
    required this.initialColor,
    required this.initialEmoji,
  });

  final String initialColor;
  final String initialEmoji;

  @override
  State<ProfilePictureEditorScreen> createState() =>
      _ProfilePictureEditorScreenState();
}

class _ProfilePictureEditorScreenState
    extends State<ProfilePictureEditorScreen> {
  late ProfilePicture _currentProfilePicture;
  String _selectedCategory = 'Smileys';

  @override
  void initState() {
    super.initState();
    _currentProfilePicture = ProfilePicture.fromData(
      widget.initialColor,
      widget.initialEmoji,
    );
  }

  void _selectColor(Color color) {
    setState(() {
      _currentProfilePicture = _currentProfilePicture.copyWith(
        backgroundColor: color,
      );
    });
  }

  void _selectEmoji(String emoji) {
    setState(() {
      _currentProfilePicture = _currentProfilePicture.copyWith(emoji: emoji);
    });
  }

  void _save() {
    context.pop({
      'color': _currentProfilePicture.backgroundColorHex,
      'emoji': _currentProfilePicture.emoji,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Edit Profile Picture',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              'Save',
              style: TextStyle(
                color: StudyColors.primary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
              ),
              child: Column(
                children: [
                  ProfilePictureWidget(
                    profilePicture: _currentProfilePicture,
                    size: 120,
                    showBorder: true,
                    borderColor: Colors.white,
                    borderWidth: 4,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Preview',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Background Color Section
                    const Text(
                      'Background Color',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildColorFamilies(),
                    const SizedBox(height: 32),

                    // Emoji Section
                    const Text(
                      'Choose Emoji',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildEmojiCategories(),
                    const SizedBox(height: 16),
                    _buildEmojiGrid(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorFamilies() {
    return Column(
      children: ProfilePictureConstants.colorFamilies.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.key,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: entry.value.map((color) {
                  final isSelected =
                      color.value == _currentProfilePicture.backgroundColor.value;
                  return GestureDetector(
                    onTap: () => _selectColor(color),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? Colors.black87
                              : Colors.grey.shade300,
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 24,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmojiCategories() {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: ProfilePictureConstants.emojiCategories.keys.length,
        itemBuilder: (context, index) {
          final category =
              ProfilePictureConstants.emojiCategories.keys.elementAt(index);
          final isSelected = category == _selectedCategory;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(category),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedCategory = category;
                  });
                }
              },
              selectedColor: StudyColors.primary,
              backgroundColor: Colors.grey.shade100,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              side: BorderSide.none,
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmojiGrid() {
    final emojis =
        ProfilePictureConstants.emojiCategories[_selectedCategory] ?? [];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: emojis.length,
      itemBuilder: (context, index) {
        final emoji = emojis[index];
        final isSelected = emoji == _currentProfilePicture.emoji;

        return GestureDetector(
          onTap: () => _selectEmoji(emoji),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? StudyColors.primary.withOpacity(0.1)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? StudyColors.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
        );
      },
    );
  }
}
