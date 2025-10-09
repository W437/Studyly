import 'dart:math';

import 'package:flutter/material.dart';

/// Profile picture configuration combining background color and emoji
class ProfilePicture {
  const ProfilePicture({
    required this.backgroundColor,
    required this.emoji,
  });

  final Color backgroundColor;
  final String emoji;

  /// Generate a random profile picture
  static ProfilePicture random() {
    final random = Random();
    final colorIndex = random.nextInt(ProfilePictureConstants.allColors.length);
    final emojiIndex = random.nextInt(ProfilePictureConstants.allEmojis.length);

    return ProfilePicture(
      backgroundColor: ProfilePictureConstants.allColors[colorIndex],
      emoji: ProfilePictureConstants.allEmojis[emojiIndex],
    );
  }

  /// Create from hex color string and emoji
  factory ProfilePicture.fromData(String hexColor, String emoji) {
    return ProfilePicture(
      backgroundColor: _colorFromHex(hexColor),
      emoji: emoji,
    );
  }

  /// Convert color to hex string
  String get backgroundColorHex => '#${backgroundColor.value.toRadixString(16).substring(2).toUpperCase()}';

  /// Helper to convert hex string to Color
  static Color _colorFromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  ProfilePicture copyWith({
    Color? backgroundColor,
    String? emoji,
  }) {
    return ProfilePicture(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      emoji: emoji ?? this.emoji,
    );
  }
}

/// Constants for profile picture customization
class ProfilePictureConstants {
  // Color families organized by hue
  static const List<Color> blues = [
    Color(0xFF3B82F6), // Blue
    Color(0xFF6366F1), // Indigo
    Color(0xFF8B5CF6), // Violet
    Color(0xFF0EA5E9), // Sky
    Color(0xFF06B6D4), // Cyan
  ];

  static const List<Color> purples = [
    Color(0xFFA855F7), // Purple
    Color(0xFFD946EF), // Fuchsia
    Color(0xFFEC4899), // Pink
    Color(0xFF9333EA), // Purple dark
    Color(0xFFC026D3), // Fuchsia dark
  ];

  static const List<Color> greens = [
    Color(0xFF10B981), // Emerald
    Color(0xFF22C55E), // Green
    Color(0xFF84CC16), // Lime
    Color(0xFF14B8A6), // Teal
    Color(0xFF059669), // Emerald dark
  ];

  static const List<Color> oranges = [
    Color(0xFFF59E0B), // Amber
    Color(0xFFF97316), // Orange
    Color(0xFFEF4444), // Red
    Color(0xFFFB923C), // Orange light
    Color(0xFFDC2626), // Red dark
  ];

  static const List<Color> neutrals = [
    Color(0xFF6B7280), // Gray
    Color(0xFF374151), // Gray dark
    Color(0xFF1F2937), // Gray darker
    Color(0xFF78716C), // Stone
    Color(0xFF57534E), // Stone dark
  ];

  /// All colors in a single list for random selection
  static List<Color> get allColors => [
    ...blues,
    ...purples,
    ...greens,
    ...oranges,
    ...neutrals,
  ];

  /// Organized color families for UI display
  static const Map<String, List<Color>> colorFamilies = {
    'Blues': blues,
    'Purples': purples,
    'Greens': greens,
    'Oranges': oranges,
    'Neutrals': neutrals,
  };

  /// Popular emojis for profile pictures
  static const List<String> allEmojis = [
    // Smileys
    '😊', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '😉',
    '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😙', '🥲', '😋',
    '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔', '🤐',
    '😐', '😑', '😶', '🙄', '😏', '😬', '😌', '😔', '😪', '🤤',
    '😴', '😷', '🤒', '🤕', '🤢', '🤮', '🤧', '🥵', '🥶', '😎',
    '🤓', '🧐', '😕', '😟', '🙁', '😮', '😯', '😲', '😳', '🥺',

    // Animals
    '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯',
    '🦁', '🐮', '🐷', '🐸', '🐵', '🐔', '🐧', '🐦', '🐤', '🦄',
    '🐝', '🐛', '🦋', '🐌', '🐞', '🐙', '🦀', '🐡', '🐠', '🐬',

    // Nature & Food
    '🌸', '🌺', '🌻', '🌷', '🌹', '🌴', '🌵', '🌲', '🍀', '🌿',
    '🍎', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🍑', '🍒', '🍍',
    '🥥', '🥝', '🍅', '🥑', '🍆', '🥕', '🌽', '🥒', '🥬', '🥦',

    // Objects & Activities
    '⚽', '🏀', '🏈', '⚾', '🎾', '🏐', '🏉', '🥏', '🎱', '🏓',
    '🏸', '🏒', '🏑', '🥍', '🏏', '🥅', '⛳', '🎯', '🏹', '🎣',
    '🎸', '🎹', '🎺', '🎷', '🥁', '🎵', '🎶', '🎤', '🎧', '🎮',
    '🎲', '🎯', '🎨', '🎭', '🎪', '🎬', '🎥', '📷', '📸', '🖼️',

    // Symbols & Others
    '⭐', '🌟', '✨', '💫', '🔥', '💧', '⚡', '☀️', '🌙', '🌈',
    '🎈', '🎉', '🎊', '🎁', '🏆', '🥇', '🥈', '🥉', '🎖️', '🏅',
    '💎', '👑', '🎓', '🎩', '👒', '🧢', '⛑️', '💼', '🎒', '👜',
  ];

  /// Categorized emojis for easier browsing
  static const Map<String, List<String>> emojiCategories = {
    'Smileys': [
      '😊', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '😉',
      '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😙', '🥲', '😋',
      '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔', '😎',
    ],
    'Animals': [
      '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯',
      '🦁', '🐮', '🐷', '🐸', '🐵', '🐔', '🐧', '🐦', '🐤', '🦄',
      '🐝', '🐛', '🦋', '🐌', '🐞', '🐙', '🦀', '🐡', '🐠', '🐬',
    ],
    'Nature': [
      '🌸', '🌺', '🌻', '🌷', '🌹', '🌴', '🌵', '🌲', '🍀', '🌿',
      '⭐', '🌟', '✨', '💫', '🔥', '💧', '⚡', '☀️', '🌙', '🌈',
    ],
    'Food': [
      '🍎', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🍑', '🍒', '🍍',
      '🥥', '🥝', '🍅', '🥑', '🍆', '🥕', '🌽', '🥒', '🥬', '🥦',
    ],
    'Activities': [
      '⚽', '🏀', '🏈', '⚾', '🎾', '🏐', '🏉', '🥏', '🎱', '🏓',
      '🎸', '🎹', '🎺', '🎷', '🥁', '🎵', '🎶', '🎤', '🎧', '🎮',
      '🎲', '🎯', '🎨', '🎭', '🎪', '🎬', '🎥', '📷', '📸', '🖼️',
    ],
    'Objects': [
      '🎈', '🎉', '🎊', '🎁', '🏆', '🥇', '🥈', '🥉', '🎖️', '🏅',
      '💎', '👑', '🎓', '🎩', '👒', '🧢', '⛑️', '💼', '🎒', '👜',
    ],
  };

  /// Default profile picture for new users
  static const ProfilePicture defaultProfilePicture = ProfilePicture(
    backgroundColor: Color(0xFF6366F1), // Indigo
    emoji: '😊',
  );
}
