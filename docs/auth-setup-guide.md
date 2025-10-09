# Authentication Setup Guide

## Current Status
- ✅ Auth is **skipped** for development (splash screen goes directly to home)
- ✅ Account page is accessible from bottom navigation
- ✅ Supabase Auth is initialized in the app
- ⚠️ OAuth providers need to be configured in Supabase Dashboard

## Supabase OAuth Support

Supabase supports the following OAuth providers out of the box:
- ✅ **Google** (recommended for Android & iOS)
- ✅ **Apple** (required for iOS App Store)
- ✅ **Facebook**
- ✅ **Twitter/X**
- ✅ GitHub, Discord, Slack, and more

## Setup Instructions for Production

### 1. Configure OAuth Providers in Supabase Dashboard

#### Google Sign-In

1. **Create OAuth credentials:**
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Create a new project or select existing
   - Enable Google+ API
   - Go to "Credentials" → "Create Credentials" → "OAuth 2.0 Client ID"
   - Configure consent screen
   - Create credentials for:
     - **Web application** (for web)
     - **iOS** (bundle ID: `com.yourcompany.studyly`)
     - **Android** (SHA-1 fingerprint from your keystore)

2. **Configure in Supabase:**
   - Go to Supabase Dashboard → Authentication → Providers
   - Enable Google
   - Add Client ID and Client Secret
   - Add authorized redirect URL: `https://your-project.supabase.co/auth/v1/callback`

#### Apple Sign-In (Required for iOS)

1. **Configure in Apple Developer:**
   - Go to [Apple Developer](https://developer.apple.com/)
   - Certificates, Identifiers & Profiles
   - Create new Service ID
   - Enable "Sign in with Apple"
   - Configure return URLs

2. **Configure in Supabase:**
   - Go to Supabase Dashboard → Authentication → Providers
   - Enable Apple
   - Add Service ID and Key ID
   - Upload .p8 private key file

#### Facebook Sign-In

1. **Create Facebook App:**
   - Go to [Facebook Developers](https://developers.facebook.com/)
   - Create a new app
   - Add "Facebook Login" product
   - Configure OAuth redirect URIs

2. **Configure in Supabase:**
   - Enable Facebook provider
   - Add App ID and App Secret

### 2. Update Flutter Code

The auth welcome screen (`lib/features/auth/presentation/auth_welcome_screen.dart`) already has the UI. You just need to wire up the buttons:

```dart
// Example: Google Sign-In
_SocialButton(
  icon: Icons.g_mobiledata,
  label: 'Continue with Google',
  onPressed: () async {
    final supabase = Supabase.instance.client;
    await supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'com.yourcompany.studyly://login-callback',
    );
  },
),

// Example: Apple Sign-In
_SocialButton(
  icon: Icons.apple,
  label: 'Continue with Apple',
  onPressed: () async {
    final supabase = Supabase.instance.client;
    await supabase.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: 'com.yourcompany.studyly://login-callback',
    );
  },
),
```

### 3. Handle Auth State

Create an auth state listener in your app:

```dart
// In bootstrap.dart or main app widget
Supabase.instance.client.auth.onAuthStateChange.listen((data) {
  final session = data.session;
  if (session != null) {
    // User is signed in
    // Navigate to home
  } else {
    // User is signed out
    // Navigate to auth screen
  }
});
```

### 4. Deep Linking Configuration

#### iOS (ios/Runner/Info.plist)
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.yourcompany.studyly</string>
    </array>
  </dict>
</array>
```

#### Android (android/app/src/main/AndroidManifest.xml)
```xml
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="com.yourcompany.studyly" />
</intent-filter>
```

### 5. User Profile Management

After sign-in, create/update user profile:

```dart
final user = Supabase.instance.client.auth.currentUser;
if (user != null) {
  // Check if profile exists
  final profile = await supabase
    .from('user_profiles')
    .select()
    .eq('user_id', user.id)
    .maybeSingle();

  if (profile == null) {
    // Create new profile
    await supabase.from('user_profiles').insert({
      'user_id': user.id,
      'email': user.email,
      'display_name': user.userMetadata?['full_name'] ?? user.email?.split('@')[0],
      'avatar_url': user.userMetadata?['avatar_url'],
    });
  }
}
```

## Testing OAuth Flow

### Development
1. Use Supabase Local Development for testing
2. Or use test accounts from OAuth providers

### Production
1. Submit apps to App Store / Google Play
2. OAuth will work with production credentials
3. Apple Sign-In is **required** for iOS App Store approval

## Security Considerations

1. **Never commit OAuth secrets** - use environment variables
2. **Enable RLS policies** - already done for user_profiles table
3. **Use PKCE flow** - Supabase handles this automatically
4. **Validate JWT tokens** - Supabase handles this server-side
5. **Set up proper redirect URLs** - whitelist only your domains

## Current Implementation

The app is set up with:
- ✅ Supabase client initialized
- ✅ RLS policies on all tables
- ✅ User profiles table ready
- ✅ Auth UI screens built
- ⚠️ OAuth buttons need to be wired up (see step 2 above)
- ⚠️ Auth state management needs to be added

## Next Steps for Production

1. Configure OAuth providers in Supabase Dashboard
2. Wire up auth buttons in `auth_welcome_screen.dart`
3. Add auth state listener
4. Configure deep linking
5. Test OAuth flow on real devices
6. Submit to app stores

## Useful Links

- [Supabase Auth Documentation](https://supabase.com/docs/guides/auth)
- [Flutter Supabase Auth Guide](https://supabase.com/docs/guides/auth/social-login/auth-google)
- [Google Sign-In Setup](https://developers.google.com/identity/sign-in/ios/start-integrating)
- [Apple Sign-In Setup](https://developer.apple.com/sign-in-with-apple/)
