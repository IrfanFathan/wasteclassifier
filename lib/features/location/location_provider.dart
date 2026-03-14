import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/constants.dart';
import 'location_repository.dart';

/// State: the UUID of the last successfully inserted location ping.
class LocationPingNotifier extends AsyncNotifier<String?> {
  Timer? _timer;

  @override
  Future<String?> build() async {
    // Start the periodic timer when the notifier is first built.
    _startTimer();
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(AppConstants.kPingInterval, (_) => _doPing());
  }

  Future<void> _doPing() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString(AppConstants.prefDeviceId);
    if (deviceId == null) {
      debugPrint(
        'LocationPingNotifier: device_id not yet registered, skipping',
      );
      return;
    }
    final id = await LocationRepository.pingOnce(deviceId);
    if (id != null) state = AsyncData(id);
  }

  /// Force an immediate ping (e.g. called from foreground service on resume).
  Future<void> pingNow() => _doPing();
}

final locationPingProvider =
    AsyncNotifierProvider<LocationPingNotifier, String?>(
      LocationPingNotifier.new,
    );
