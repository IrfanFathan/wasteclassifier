import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/constants.dart';

class DeviceRepository {
  /// Returns the stored WASTO device UUID, registering the device on first call.
  ///
  /// Registration logic:
  ///   1. Check SharedPreferences for an already-stored device_id.
  ///   2. If absent, upsert a row in `devices` using a stable device identifier
  ///      as the conflict key (Android ID or iOS identifierForVendor).
  ///   3. Persist the returned id for all future calls.
  static Future<String> registerOrFetchDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(AppConstants.prefDeviceId);
    if (stored != null && stored.isNotEmpty) return stored;

    final supabase = Supabase.instance.client;
    final deviceId = await _stableDeviceId();
    final deviceName = await _deviceModel();

    final response = await supabase
        .from(AppConstants.tableDevices)
        .upsert(
          {
            'device_name': deviceName,
            'gsm_iccid': deviceId,
            'last_seen_at': DateTime.now().toIso8601String(),
          },
          onConflict: 'gsm_iccid',
        )
        .select('id')
        .single();

    final id = response['id'] as String;
    await prefs.setString(AppConstants.prefDeviceId, id);
    debugPrint('DeviceRepository: registered/fetched device_id=$id');
    return id;
  }

  /// Update `last_seen_at` every time the app comes to foreground.
  static Future<void> updateLastSeen(String deviceId) async {
    try {
      await Supabase.instance.client
          .from(AppConstants.tableDevices)
          .update({'last_seen_at': DateTime.now().toIso8601String()})
          .eq('id', deviceId);
    } catch (e) {
      debugPrint('DeviceRepository: updateLastSeen failed: $e');
    }
  }

  static Future<String> _deviceModel() async {
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        return info.model;
      } else if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        return info.utsname.machine;
      }
    } catch (_) {}
    return 'Unknown';
  }

  /// Returns a stable per-device identifier used as the Supabase upsert key.
  static Future<String> _stableDeviceId() async {
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        return 'android_${info.id}';
      } else if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        return 'ios_${info.identifierForVendor ?? info.name}';
      }
    } catch (_) {}
    return 'unknown_${DateTime.now().millisecondsSinceEpoch}';
  }
}
