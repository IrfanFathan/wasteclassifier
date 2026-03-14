class AppConstants {
  // Use 10.0.2.2 for Android emulator to access local host, or 0.0.0.0 for actual network
  // Using 0.0.0.0 as requested.
  static const String httpServerHost = '0.0.0.0';
  static const int httpServerPort = 8080;

  // Supabase Table Names
  static const String tableWasteDetections = 'waste_detections';
  static const String tableLocationLogs = 'location_logs';

  // Shared Preferences Keys
  static const String prefLocationTrackingEnabled = 'location_tracking_enabled';

  // Environment variables (replace with your actual Supabase URL and anon key)
  // Since environment variables from build/launch can be tricky without flutter_dotenv,
  // we are defining them here for simplicity. In production, consider --dart-define.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://YOUR_PROJECT_ID.supabase.co');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'YOUR_ANON_KEY');
}
