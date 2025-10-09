import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for handling authentication operations
class AuthService {
  final SupabaseClient _supabase;

  AuthService(this._supabase);

  /// Get current user
  User? get currentUser => _supabase.auth.currentUser;

  /// Check if user is signed in
  bool get isSignedIn => currentUser != null;

  /// Stream of auth state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Sign in with Google
  Future<AuthResponse> signInWithGoogle() async {
    return await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'com.studyly.app://login-callback',
    );
  }

  /// Sign in with Apple
  Future<AuthResponse> signInWithApple() async {
    return await _supabase.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: 'com.studyly.app://login-callback',
    );
  }

  /// Sign in with Facebook
  Future<AuthResponse> signInWithFacebook() async {
    return await _supabase.auth.signInWithOAuth(
      OAuthProvider.facebook,
      redirectTo: 'com.studyly.app://login-callback',
    );
  }

  /// Sign in with email and password
  Future<AuthResponse> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Sign up with email and password
  Future<AuthResponse> signUpWithEmailPassword({
    required String email,
    required String password,
    String? displayName,
  }) async {
    return await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        if (displayName != null) 'display_name': displayName,
      },
    );
  }

  /// Sign out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  /// Reset password
  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  /// Create or update user profile after sign in
  Future<void> syncUserProfile() async {
    final user = currentUser;
    if (user == null) return;

    // Check if profile exists
    final existingProfile = await _supabase
        .from('user_profiles')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();

    if (existingProfile == null) {
      // Create new profile
      await _supabase.from('user_profiles').insert({
        'user_id': user.id,
        'email': user.email,
        'display_name': user.userMetadata?['display_name'] ??
            user.userMetadata?['full_name'] ??
            user.email?.split('@')[0] ??
            'User',
        'avatar_url': user.userMetadata?['avatar_url'],
        'created_at': DateTime.now().toIso8601String(),
      });
    } else {
      // Update existing profile with latest info
      await _supabase.from('user_profiles').update({
        'email': user.email,
        'avatar_url': user.userMetadata?['avatar_url'],
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('user_id', user.id);
    }
  }
}
