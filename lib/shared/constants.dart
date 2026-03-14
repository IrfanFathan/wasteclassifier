class AppConstants {
  // ── ESP32 / HTTP server (existing feature) ─────────────────────────────
  static const String httpServerHost = '0.0.0.0';
  static const int httpServerPort = 8080;

  // ── Old Supabase table names (kept for ESP32 feature) ──────────────────
  static const String tableWasteDetections = 'waste_detections';
  static const String tableLocationLogs = 'location_logs';

  // ── WASTO Tracker table names ──────────────────────────────────────────
  static const String tableDevices = 'devices';
  static const String tableLocationPings = 'location_pings';
  static const String tableDetectionEvents = 'detection_events';
  static const String tableWasteClasses = 'waste_classes';

  // ── Supabase Storage ───────────────────────────────────────────────────
  static const String storageBucketDetections = 'detection-frames';

  // ── WASTO Tracker intervals / thresholds ──────────────────────────────
  static const Duration kPingInterval = Duration(minutes: 2);
  static const Duration kDetectionCooldown = Duration(seconds: 5);
  static const double kDetectionConfidenceThreshold = 0.45;

  // ── Shared Preferences Keys ────────────────────────────────────────────
  static const String prefLocationTrackingEnabled = 'location_tracking_enabled';
  static const String prefDeviceId = 'wasto_device_id';
}
