import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

import '../shared/constants.dart';
import '../shared/models/location_log.dart';
import 'location_service.dart';

class BackgroundService {
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        // this will be executed when app is in foreground or background in separated isolate
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
      ),
      iosConfiguration: IosConfiguration(
        // auto start service
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase because this is a separate isolate
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  final String? deviceId = await _getDeviceId();

  // We set a periodic timer for every 2 minutes
  Timer.periodic(const Duration(minutes: 2), (timer) async {
    final prefs = await SharedPreferences.getInstance();
    final isTracking = prefs.getBool(AppConstants.prefLocationTrackingEnabled) ?? false;

    if (isTracking) {
      print('Background Service: Tracking is ON. Fetching location...');
      final loc = await LocationService.getCurrentLocation();
      
      if (loc != null) {
        final log = LocationLog(
          latitude: loc.latitude,
          longitude: loc.longitude,
          recordedAt: DateTime.now(),
          deviceId: deviceId,
        );

        try {
          await Supabase.instance.client
              .from(AppConstants.tableLocationLogs)
              .insert(log.toJson());
          print('Background Service: Successfully inserted location info.');
        } catch (e) {
          print('Background Service: Failed to insert location log: $e');
        }
      } else {
        print('Background Service: Location disabled or permissions missing.');
      }
    } else {
      print('Background Service: Tracking is OFF.');
    }
  });
}

Future<String?> _getDeviceId() async {
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  try {
    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      return info.id; // unique ID on Android
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      return info.identifierForVendor;
    }
  } catch (e) {
    print('Failed to get device info: $e');
  }
  return null;
}
