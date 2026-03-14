import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/waste_detection.dart';
import '../../shared/constants.dart';
import '../../core/location_service.dart';
import '../../core/supabase_client.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

final deviceIdProvider = FutureProvider<String?>((ref) async {
  final deviceInfoPlugin = DeviceInfoPlugin();
  try {
    if (Platform.isAndroid) {
      final info = await deviceInfoPlugin.androidInfo;
      return info.id;
    } else if (Platform.isIOS) {
      final info = await deviceInfoPlugin.iosInfo;
      return info.identifierForVendor;
    }
  } catch (e) {
    return null;
  }
  return null;
});

// A provider that listens to the HTTP server and handles a new detection
class DetectionNotifier extends StateNotifier<AsyncValue<WasteDetection?>> {
  final Ref ref;

  DetectionNotifier(this.ref) : super(const AsyncValue.data(null));

  Future<void> handleNewDetection(String wasteType) async {
    state = const AsyncValue.loading();
    
    try {
      final loc = await LocationService.getCurrentLocation();
      final deviceId = await ref.read(deviceIdProvider.future);

      final detection = WasteDetection(
        wasteType: wasteType,
        latitude: loc?.latitude,
        longitude: loc?.longitude,
        locationSource: loc?.source ?? 'unavailable',
        detectedAt: DateTime.now(),
        deviceId: deviceId,
      );

      final supabase = ref.read(supabaseProvider);
      
      await supabase
          .from(AppConstants.tableWasteDetections)
          .insert(detection.toJson());

      state = AsyncValue.data(detection);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final detectionControllerProvider = 
  StateNotifierProvider<DetectionNotifier, AsyncValue<WasteDetection?>>((ref) {
    return DetectionNotifier(ref);
});
