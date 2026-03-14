import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../../shared/constants.dart';
import 'location_repository.dart';

const String kWorkmanagerTaskName = 'wasto_location_ping';
const String kWorkmanagerTaskTag = 'locationPingTask';

/// Workmanager callback dispatcher — runs in a separate isolate.
///
/// Provides the 15-minute background fallback when the foreground service
/// has been killed by the OS.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await dotenv.load();
      await Supabase.initialize(
        url: dotenv.env['SUPABASE_URL']!,
        anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      );

      final prefs = await SharedPreferences.getInstance();
      final deviceId =
          inputData?['device_id'] as String? ??
          prefs.getString(AppConstants.prefDeviceId);

      if (deviceId != null) {
        await LocationRepository.pingOnce(deviceId);
      }
    } catch (e) {
      debugPrint('callbackDispatcher: error: $e');
      return false;
    }
    return true;
  });
}

/// Registers the periodic workmanager task (15-min OS floor on Android).
Future<void> registerWorkmanagerTask(String deviceId) async {
  await Workmanager().registerPeriodicTask(
    kWorkmanagerTaskName,
    kWorkmanagerTaskTag,
    frequency: const Duration(minutes: 15),
    inputData: {'device_id': deviceId},
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
}
