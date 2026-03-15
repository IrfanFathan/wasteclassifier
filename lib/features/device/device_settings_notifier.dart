import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/background_service.dart';
import '../../features/location/location_repository.dart';
import '../../shared/constants.dart';
import 'device_repository.dart';

/// Immutable snapshot of all device settings shown on the settings screen.
class DeviceSettings {
  final String deviceId;
  final String deviceName;
  final bool isActive;
  final bool locationTrackingEnabled;
  final bool detectionLoggingEnabled;
  final DateTime? registeredAt;
  final DateTime? lastSeenAt;

  const DeviceSettings({
    required this.deviceId,
    required this.deviceName,
    required this.isActive,
    required this.locationTrackingEnabled,
    required this.detectionLoggingEnabled,
    this.registeredAt,
    this.lastSeenAt,
  });

  DeviceSettings copyWith({
    String? deviceId,
    String? deviceName,
    bool? isActive,
    bool? locationTrackingEnabled,
    bool? detectionLoggingEnabled,
    DateTime? registeredAt,
    DateTime? lastSeenAt,
  }) {
    return DeviceSettings(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      isActive: isActive ?? this.isActive,
      locationTrackingEnabled:
          locationTrackingEnabled ?? this.locationTrackingEnabled,
      detectionLoggingEnabled:
          detectionLoggingEnabled ?? this.detectionLoggingEnabled,
      registeredAt: registeredAt ?? this.registeredAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class DeviceSettingsNotifier extends AsyncNotifier<DeviceSettings> {
  @override
  Future<DeviceSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString(AppConstants.prefDeviceId) ?? '';

    final locationEnabled =
        prefs.getBool(AppConstants.prefLocationTrackingEnabled) ?? true;
    final detectionEnabled =
        prefs.getBool(AppConstants.prefDetectionLoggingEnabled) ?? true;

    // Fetch live row from Supabase; fall back gracefully if offline.
    String deviceName = 'This Device';
    bool isActive = true;
    DateTime? registeredAt;
    DateTime? lastSeenAt;

    if (deviceId.isNotEmpty) {
      final row = await DeviceRepository.fetchDevice(deviceId);
      if (row != null) {
        deviceName = (row['device_name'] as String?) ?? deviceName;
        isActive = (row['is_active'] as bool?) ?? true;
        registeredAt = row['registered_at'] != null
            ? DateTime.tryParse(row['registered_at'] as String)
            : null;
        lastSeenAt = row['last_seen_at'] != null
            ? DateTime.tryParse(row['last_seen_at'] as String)
            : null;
      }
    }

    return DeviceSettings(
      deviceId: deviceId,
      deviceName: deviceName,
      isActive: isActive,
      locationTrackingEnabled: locationEnabled,
      detectionLoggingEnabled: detectionEnabled,
      registeredAt: registeredAt,
      lastSeenAt: lastSeenAt,
    );
  }

  // ── Toggle: device active status ─────────────────────────────────────────

  Future<void> setActive(bool value) async {
    final DeviceSettings? current = switch (state) { AsyncData(:final value) => value, _ => null };
    if (current == null) return;

    // Optimistic update so the UI reflects instantly.
    state = AsyncData(current.copyWith(isActive: value));

    await DeviceRepository.setActiveStatus(current.deviceId, active: value);
  }

  // ── Toggle: location tracking ─────────────────────────────────────────────

  Future<void> setLocationTracking(bool value) async {
    final DeviceSettings? current = switch (state) { AsyncData(:final value) => value, _ => null };
    if (current == null) return;

    state = AsyncData(current.copyWith(locationTrackingEnabled: value));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefLocationTrackingEnabled, value);

    // Start / stop the foreground service to match the toggle.
    if (value) {
      await WastoForegroundService.start();
    } else {
      await WastoForegroundService.stop();
    }

    debugPrint('DeviceSettings: locationTracking=$value');
  }

  // ── Toggle: detection logging ─────────────────────────────────────────────

  Future<void> setDetectionLogging(bool value) async {
    final DeviceSettings? current = switch (state) { AsyncData(:final value) => value, _ => null };
    if (current == null) return;

    state = AsyncData(current.copyWith(detectionLoggingEnabled: value));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefDetectionLoggingEnabled, value);

    debugPrint('DeviceSettings: detectionLogging=$value');
  }

  // ── Update device name ────────────────────────────────────────────────────

  Future<void> updateDeviceName(String name) async {
    final DeviceSettings? current = switch (state) { AsyncData(:final value) => value, _ => null };
    if (current == null || name.trim().isEmpty) return;

    state = AsyncData(current.copyWith(deviceName: name.trim()));
    await DeviceRepository.updateDeviceName(current.deviceId, name);
  }

  // ── Sync now ──────────────────────────────────────────────────────────────

  /// Pushes an immediate location ping and refreshes `last_seen_at`.
  Future<void> syncNow() async {
    final DeviceSettings? current = switch (state) { AsyncData(:final value) => value, _ => null };
    if (current == null || current.deviceId.isEmpty) return;

    await Future.wait([
      LocationRepository.pingOnce(current.deviceId),
      DeviceRepository.updateLastSeen(current.deviceId),
    ]);

    // Reload the lastSeenAt field from Supabase.
    final row = await DeviceRepository.fetchDevice(current.deviceId);
    if (row != null) {
      final lastSeenAt = row['last_seen_at'] != null
          ? DateTime.tryParse(row['last_seen_at'] as String)
          : null;
      state = AsyncData(current.copyWith(lastSeenAt: lastSeenAt));
    }
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────

final deviceSettingsProvider =
    AsyncNotifierProvider<DeviceSettingsNotifier, DeviceSettings>(
  DeviceSettingsNotifier.new,
);
