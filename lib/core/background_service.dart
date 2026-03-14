import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/location/location_repository.dart';
import '../shared/constants.dart';

// ─── Task Handler ─────────────────────────────────────────────────────────────

/// Called by the OS in a separate isolate when the foreground service starts.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_WastoTaskHandler());
}

class _WastoTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('WastoForegroundService: task started at $timestamp');
    // Re-initialize Supabase because this may run in its own isolate.
    try {
      await dotenv.load();
      await Supabase.initialize(
        url: dotenv.env['SUPABASE_URL']!,
        anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      );
    } catch (e) {
      // Already initialized — safe to ignore.
      debugPrint('WastoForegroundService: Supabase init: $e');
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString(AppConstants.prefDeviceId);
    if (deviceId == null) {
      debugPrint('WastoForegroundService: device_id not set, skipping ping');
      return;
    }
    debugPrint('WastoForegroundService: pinging location for device=$deviceId');
    await LocationRepository.pingOnce(deviceId);
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('WastoForegroundService: task destroyed');
  }
}

// ─── WastoForegroundService ───────────────────────────────────────────────────

class WastoForegroundService {
  /// Configures the foreground task options.  Call once during app startup
  /// (before [start]).
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'wasto_location_channel',
        channelName: 'WASTO Location Tracking',
        channelDescription: 'Sends a GPS ping every 2 minutes.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(
          AppConstants.kPingInterval.inMilliseconds,
        ),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Starts the foreground service (shows a persistent notification).
  static Future<ServiceRequestResult> start() async {
    if (await FlutterForegroundTask.isRunningService) {
      return FlutterForegroundTask.restartService();
    }
    return FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'WASTO Tracker',
      notificationText: 'Location tracking active — ping every 2 min',
      callback: startCallback,
    );
  }

  /// Stops the foreground service.
  static Future<ServiceRequestResult> stop() {
    return FlutterForegroundTask.stopService();
  }
}
