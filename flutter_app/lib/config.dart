/// App-level configuration constants.
///
/// SETUP REQUIRED:
/// ──────────────
/// 1. Go to Google Cloud Console → APIs & Services → Credentials
/// 2. Create an OAuth 2.0 Client ID → type: "Web application"
///    - Leave Authorized redirect URIs empty (not needed for mobile server-auth-code flow)
/// 3. Copy the "Client ID" value and paste it below as [googleWebClientId]
/// 4. Copy the "Client Secret" → add to Render as GOOGLE_CLIENT_SECRET
/// 5. The same Client ID → add to Render as GOOGLE_CLIENT_ID
///
/// Also ensure you have an Android OAuth client registered:
/// - In Google Cloud Console → Create OAuth 2.0 Client ID → type: "Android"
/// - Package name: com.adimeh.cura
/// - SHA-1: run `cd android && ./gradlew signingReport` to get the debug SHA-1
///
/// NOTE: If you set googleWebClientId to empty string, Google Sign-In will still
/// work for login but serverAuthCode will be null and Calendar won't connect.

class AppConfig {
  // Web Application OAuth 2.0 Client ID from Google Cloud Console.
  // Must match the GOOGLE_CLIENT_ID env var on your Render backend.
  static const String googleWebClientId =
      '594980338208-dvm0a89fl7kbv0vd3b7nfhnrqt4ebcbn.apps.googleusercontent.com';
}
