import 'package:equatable/equatable.dart';

import 'study_content_type.dart';

class UserProfile extends Equatable {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.email,
    required this.avatarUrl,
    required this.activePlan,
    required this.focusAreas,
  });

  final String id;
  final String displayName;
  final String email;
  final String avatarUrl;
  final String activePlan;
  final List<StudyMaterialTag> focusAreas;

  @override
  List<Object?> get props => [
    id,
    displayName,
    email,
    avatarUrl,
    activePlan,
    focusAreas,
  ];
}
