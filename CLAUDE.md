# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Studyly is a Flutter-based educational app that provides AI-powered study tools including flashcards, explanations, exercises, and a study planner. The app uses a **local-first sync architecture** with Supabase as the backend.

## Development Commands

### Running the App
```bash
flutter run
```

### Building
```bash
# iOS
flutter build ios

# Android
flutter build apk
flutter build appbundle

# Web
flutter build web
```

### Code Generation
The app uses Isar for local database storage, which requires code generation:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Testing
```bash
# Run all tests
flutter test

# Run a specific test file
flutter test test/core/data/local_first_study_repository_test.dart

# Run tests with coverage
flutter test --coverage
```

### Linting
```bash
flutter analyze
```

## Architecture

### Local-First Sync Pattern

The app implements a **local-first architecture** where:
1. All data is stored locally in Isar (NoSQL database)
2. Supabase is used for remote sync when cloud sync is enabled
3. Users can toggle cloud sync on/off via `syncSettingsProvider`
4. The `LocalFirstStudyRepository` handles sync logic transparently

**Key Pattern:**
- Read from local Isar database (instant)
- Write to local first, then sync to Supabase if enabled
- Watch streams from Isar for reactive UI updates

### Feature Structure

Features follow a clean architecture pattern with:
- `presentation/` - Screens and widgets
- `application/` - Controllers (Riverpod StateNotifier)
- `domain/` - Models and business logic (when needed)

### State Management

**Riverpod patterns used:**
- `Provider` - Immutable dependencies (repositories, services)
- `StateNotifierProvider` - Mutable state with controllers
- `StreamProvider` - Reactive data streams from Isar
- `FutureProvider` - Async data loading

**Example:**
```dart
final userProfileProvider = StreamProvider<UserProfile>((ref) async* {
  final repository = ref.watch(studyRepositoryProvider);
  await repository.fetchProfile();
  yield* repository.watchProfile();
});
```

### Navigation

Uses `go_router` with declarative routes defined in `lib/app/navigation/routes.dart`:
- Routes are defined as enum `AppRoute`
- Bottom navigation handled by shell route with persistent state
- Deep linking supported for scan/study-set flows

### Authentication Flow

1. **AuthWelcomeScreen** - Entry point with social login buttons
2. **SignInScreen** - Email/password sign in
3. **SignUpScreen** - Email/password registration with profile creation
4. **QuestionnaireFlowScreen** - Post-signup onboarding (9 pages)
5. User profile created in `user_profiles` table with:
   - Random profile picture (emoji + background color)
   - Default plan: "Free"
   - Default focus areas: [0, 1, 2]

### Scan Feature Architecture

The scan feature is a multi-step flow:
1. **ScanCaptureScreen** - Choose camera or gallery
2. **CustomCameraScreen** - Custom camera interface (if camera selected)
3. **ScanPreviewScreen** - Preview and crop scanned image
4. **ScanOcrScreen** - ML Kit text extraction
5. **ScanActionChooserScreen** - Choose generation type (flashcard/explanation/exercise)
6. **GenerationReviewScreen** - Review and save AI-generated content

**Scan Controllers:**
- `scanController` - Manages scanned items (camera/gallery import)
- `flashcardGenerationController` - Generates flashcards from text
- `explanationGenerationController` - Generates explanations
- `exerciseGenerationController` - Generates practice exercises

### Data Layer

**Isar Entities** (local storage):
- `UserProfileEntity`
- `StudySetEntity`
- `StudyPlanTaskEntity`
- `StudyDocumentEntity`
- `ChatMessageEntity`
- `ScannedItemEntity`
- `FlashcardEntity`
- `ExplanationDocEntity`
- `ExerciseEntity`
- `GenerationResultEntity`

**Supabase Tables** (remote sync):
- `user_profiles` - User account data
- Row Level Security (RLS) enabled on all tables
- Users can only access their own data

### UI Conventions

**Reusable Components** (`lib/ui/widgets/`):
- `app_buttons.dart` - PrimaryButton, SecondaryButton, TextGhostButton
  - No Material ripple effects (uses `NoSplash.splashFactory`)
  - Simple overlay on press (lighter shade)
  - No elevation or shadows
- `filled_text_field.dart` - Consistent text inputs
- `surface_card.dart` - Card containers
- `tag_pill.dart` - Category/tag chips

**Theme**:
- Design tokens in `lib/ui/theme/color_tokens.dart`
- Spacing constants in `lib/ui/theme/spacing.dart`
- Primary color: StudyColors.primary (teal)

**Haptic Feedback**:
- Use `HapticFeedback.lightImpact()` for navigation actions
- Use `HapticFeedback.selectionClick()` for selection/scroll interactions

## Important Notes

### Database Initialization

On first run, the bootstrap clears old Isar data (debug mode only):
```dart
const clearOldData = true; // Set to false after first run
```

### Supabase Configuration

Supabase credentials are in `lib/app/config/supabase_config.dart`. These are public anon keys (safe for client-side).

**Supabase MCP Access:**
This project has Supabase MCP (Model Context Protocol) configured. Use MCP tools for all database-related operations including migrations, queries, schema inspection, and checking RLS policies.

### Authentication State

User authentication state is managed by Supabase Auth:
- `Supabase.instance.client.auth.currentUser` - Get current user
- Profile data synced to `user_profiles` table on sign-up/sign-in
- Profile watched via `userProfileProvider` StreamProvider

### Cloud Sync Toggle

Users can enable/disable cloud sync via the Account page:
- Toggle stored in SharedPreferences
- Managed by `syncSettingsProvider`
- Repository automatically adjusts sync behavior

### Content Generation

AI content generation happens via placeholder logic (TODO: integrate OpenAI API):
- Flashcard generation: Extracts Q&A pairs from text
- Explanation generation: Creates study explanations
- Exercise generation: Creates practice problems
- All stored locally in Isar with optional Supabase sync
