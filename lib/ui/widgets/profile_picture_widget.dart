import 'package:flutter/material.dart';

import '../../core/models/profile_picture.dart';

/// Widget to display user profile picture (background color + emoji)
class ProfilePictureWidget extends StatelessWidget {
  const ProfilePictureWidget({
    super.key,
    required this.profilePicture,
    this.size = 48,
    this.showBorder = false,
    this.borderColor,
    this.borderWidth = 2,
  });

  final ProfilePicture profilePicture;
  final double size;
  final bool showBorder;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: profilePicture.backgroundColor,
        shape: BoxShape.circle,
        border: showBorder
            ? Border.all(
                color: borderColor ?? Colors.white,
                width: borderWidth,
              )
            : null,
      ),
      child: Center(
        child: Text(
          profilePicture.emoji,
          style: TextStyle(
            fontSize: size * 0.5, // Emoji size is 50% of container
          ),
        ),
      ),
    );
  }
}

/// Widget to display user profile picture from hex color and emoji strings
class ProfilePictureFromData extends StatelessWidget {
  const ProfilePictureFromData({
    super.key,
    required this.hexColor,
    required this.emoji,
    this.size = 48,
    this.showBorder = false,
    this.borderColor,
    this.borderWidth = 2,
  });

  final String hexColor;
  final String emoji;
  final double size;
  final bool showBorder;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return ProfilePictureWidget(
      profilePicture: ProfilePicture.fromData(hexColor, emoji),
      size: size,
      showBorder: showBorder,
      borderColor: borderColor,
      borderWidth: borderWidth,
    );
  }
}
