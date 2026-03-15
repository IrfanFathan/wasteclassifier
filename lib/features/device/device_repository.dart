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
        .upsert({
          'device_name': deviceName,
          'gsm_iccid': deviceId,
          'last_seen_at': DateTime.now().toIso8601String(),
        }, onConflict: 'gsm_iccid')
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

  /// Fetches the full device row from Supabase by UUID.
  /// Returns null if the row cannot be retrieved.
  static Future<Map<String, dynamic>?> fetchDevice(String deviceId) async {
    try {
      return await Supabase.instance.client
          .from(AppConstants.tableDevices)
          .select()
          .eq('id', deviceId)
          .single();
    } catch (e) {
      debugPrint('DeviceRepository: fetchDevice failed: $e');
      return null;
    }
  }

  /// Sets `is_active` on this device row in Supabase.
  static Future<void> setActiveStatus(
    String deviceId, {
    required bool active,
  }) async {
    try {
      await Supabase.instance.client
          .from(AppConstants.tableDevices)
          .update({'is_active': active})
          .eq('id', deviceId);
      debugPrint(
        'DeviceRepository: is_active=$active for device_id=$deviceId',
      );
    } catch (e) {
      debugPrint('DeviceRepository: setActiveStatus failed: $e');
      rethrow;
    }
  }

  /// Updates `device_name` in Supabase.
  static Future<void> updateDeviceName(
    String deviceId,
    String name,
  ) async {
    try {
      await Supabase.instance.client
          .from(AppConstants.tableDevices)
          .update({'device_name': name.trim()})
          .eq('id', deviceId);
    } catch (e) {
      debugPrint('DeviceRepository: updateDeviceName failed: $e');
      rethrow;
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
