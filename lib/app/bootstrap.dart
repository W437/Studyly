import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/data/models/chat_message_entity.dart';
import '../core/data/models/exercise_entity.dart';
import '../core/data/models/explanation_doc_entity.dart';
import '../core/data/models/flashcard_entity.dart';
import '../core/data/models/generation_result_entity.dart';
import '../core/data/models/scanned_item_entity.dart';
import '../core/data/models/study_document_entity.dart';
import '../core/data/models/study_plan_task_entity.dart';
import '../core/data/models/study_set_entity.dart';
import '../core/data/models/user_profile_entity.dart';
import 'config/supabase_config.dart';

Future<void> bootstrap(Widget app) async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize Supabase
      await Supabase.initialize(
        url: SupabaseConfig.projectUrl,
        anonKey: SupabaseConfig.anonKey,
      );

      // Initialize Isar
      final dir = await getApplicationDocumentsDirectory();
      final isar = await Isar.open(
        [
          UserProfileEntitySchema,
          StudySetEntitySchema,
          StudyPlanTaskEntitySchema,
          StudyDocumentEntitySchema,
          ChatMessageEntitySchema,
          ScannedItemEntitySchema,
          FlashcardEntitySchema,
          ExplanationDocEntitySchema,
          ExerciseEntitySchema,
          GenerationResultEntitySchema,
        ],
        directory: dir.path,
      );

      // TEMPORARY: Clear old seed data (set to false after first run)
      const clearOldData = false; // Changed to false - no longer clearing data
      if (clearOldData && kDebugMode) {
        debugPrint('🧹 Clearing old seed data from Isar database...');
        await isar.writeTxn(() async {
          await isar.clear();
        });
        debugPrint('✅ Old seed data cleared!');
      }

      runApp(
        ProviderScope(
          overrides: [
            isarProvider.overrideWithValue(isar),
          ],
          child: app,
        ),
      );
    },
    (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Uncaught error: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    },
  );
}

// Provider for Isar instance
final isarProvider = Provider<Isar>((ref) {
  throw UnimplementedError('Isar instance must be provided in bootstrap');
});
