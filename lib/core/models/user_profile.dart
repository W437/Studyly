import 'package:equatable/equatable.dart';

import 'profile_picture.dart';
import 'study_content_type.dart';

class UserProfile extends Equatable {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.email,
    required this.avatarUrl,
    required this.activePlan,
    required this.focusAreas,
    required this.profileBgColor,
    required this.profileEmoji,
  });

  final String id;
  final String displayName;
  final String email;
  final String avatarUrl;
  final String activePlan;
  final List<StudyMaterialTag> focusAreas;
  final String profileBgColor; // Hex color string
  final String profileEmoji;

  /// Get profile picture from background color and emoji
  ProfilePicture get profilePicture {
    return ProfilePicture.fromData(profileBgColor, profileEmoji);
  }

  UserProfile copyWith({
    String? id,
    String? displayName,
    String? email,
    String? avatarUrl,
    String? activePlan,
    List<StudyMaterialTag>? focusAreas,
    String? profileBgColor,
    String? profileEmoji,
  }) {
    return UserProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      activePlan: activePlan ?? this.activePlan,
      focusAreas: focusAreas ?? this.focusAreas,
      profileBgColor: profileBgColor ?? this.profileBgColor,
      profileEmoji: profileEmoji ?? this.profileEmoji,
    );
  }

  @override
  List<Object?> get props => [
    id,
    displayName,
    email,
    avatarUrl,
    activePlan,
    focusAreas,
    profileBgColor,
    profileEmoji,
  ];
}
