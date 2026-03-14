import 'package:geolocator/geolocator.dart';

class LocationResult {
  final double latitude;
  final double longitude;
  final String source;

  LocationResult({
    required this.latitude,
    required this.longitude,
    required this.source,
  });
}

class LocationService {
  /// Request `locationWhenInUse` permission.
  static Future<bool> requestForegroundPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  /// Request `locationAlways` permission (required for background tracking).
  static Future<bool> requestBackgroundPermission() async {
    final granted = await requestForegroundPermission();
    if (!granted) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always) return true;

    // We must request Always permission explicitly in some scenarios, but since API 30+,
    // it usually redirects to settings. Geolocator wraps this behavior.
    if (permission == LocationPermission.whileInUse) {
      // Show rationale here before calling requestPermission in a real app if possible.
    }

    permission = await Geolocator.requestPermission();
    return permission == LocationPermission.always;
  }

  /// Gets the current location. 
  /// Tries getting accuracy. Defaults to high (GPS), falls back if unavailable.
  static Future<LocationResult?> getCurrentLocation() async {
    final hasPermission = await requestForegroundPermission();
    if (!hasPermission) return null;

    try {
      // First try GPS/High accuracy
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      return LocationResult(
        latitude: position.latitude,
        longitude: position.longitude,
        source: 'gps',
      );
    } catch (e) {
      // Fallback to coarse/medium accuracy (Network/GSM)
      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 5),
        );
        return LocationResult(
          latitude: position.latitude,
          longitude: position.longitude,
          source: 'gsm',
        );
      } catch (e2) {
        return null;
      }
    }
  }
}
