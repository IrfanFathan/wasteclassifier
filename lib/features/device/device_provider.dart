import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'device_repository.dart';

/// Resolves (and registers if needed) the WASTO device UUID.
///
/// Cached: Riverpod will keep this alive for the lifetime of the app.
final deviceIdProvider = FutureProvider<String>((ref) async {
  return DeviceRepository.registerOrFetchDeviceId();
});
