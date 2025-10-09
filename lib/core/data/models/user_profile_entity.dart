import 'package:isar/isar.dart';

part 'user_profile_entity.g.dart';

@collection
class UserProfileEntity {
  Id id = Isar.autoIncrement;

  late String userId;
  late String displayName;
  late String email;
  late String avatarUrl;
  late String activePlan;
  late List<int> focusAreaIndexes;

  UserProfileEntity();

  UserProfileEntity.create({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.avatarUrl,
    required this.activePlan,
    required this.focusAreaIndexes,
  });
}
