import 'package:isar/isar.dart';

part 'study_plan_task_entity.g.dart';

@collection
class StudyPlanTaskEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String taskId;

  late String title;
  late DateTime dueDate;
  late int contentTypeIndex;
  late bool isCompleted;

  StudyPlanTaskEntity();

  StudyPlanTaskEntity.create({
    required this.taskId,
    required this.title,
    required this.dueDate,
    required this.contentTypeIndex,
    required this.isCompleted,
  });
}
