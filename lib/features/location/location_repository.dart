import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/location_service.dart';
import '../../shared/constants.dart';
import '../../shared/models/location_ping.dart';

class LocationRepository {
  /// Fetches the current GPS position and inserts a row into `location_pings`.
  /// Returns the new row's UUID, or null on failure.
  ///
  /// GSM cell tower fields (gsmCellId, networkProvider, signalStrength) are
  /// left null — they require native telephony APIs that are not bundled.
  static Future<String?> pingOnce(String deviceId) async {
    final loc = await LocationService.getCurrentLocation();
    if (loc == null) {
      debugPrint('LocationRepository: no location available, skipping ping');
      return null;
    }

    final ping = LocationPing(
      deviceId: deviceId,
      latitude: loc.latitude,
      longitude: loc.longitude,
      recordedAt: DateTime.now(),
    );

    try {
      final response = await Supabase.instance.client
          .from(AppConstants.tableLocationPings)
          .insert(ping.toJson())
          .select('id')
          .single();
      final id = response['id'] as String;
      debugPrint('LocationRepository: ping inserted id=$id');
      return id;
    } catch (e) {
      debugPrint('LocationRepository: insert failed: $e');
      return null;
    }
  }

  /// Returns the UUID of the most recent ping for [deviceId] recorded within
  /// the last [withinMinutes] minutes, or null if none exists.
  static Future<String?> latestPingId(
    String deviceId, {
    int withinMinutes = 3,
  }) async {
    try {
      final cutoff = DateTime.now()
          .subtract(Duration(minutes: withinMinutes))
          .toIso8601String();
      final row = await Supabase.instance.client
          .from(AppConstants.tableLocationPings)
          .select('id')
          .eq('device_id', deviceId)
          .gte('recorded_at', cutoff)
          .order('recorded_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return row?['id'] as String?;
    } catch (e) {
      debugPrint('LocationRepository: latestPingId failed: $e');
      return null;
    }
  }
}
