import 'dart:convert';
import 'package:http/http.dart' as http;

/// Handles HTTP communication with the ESP32 hotspot.
class Esp32Service {
  // Singleton pattern
  Esp32Service._internal();
  static final Esp32Service _instance = Esp32Service._internal();
  factory Esp32Service() => _instance;

  // The default IP address for an ESP32 hosting a softAP is 192.168.4.1
  static const String esp32Ip = '192.168.4.1';
  static const String baseUrl = 'http://$esp32Ip';

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  /// Pings the ESP32 to verify connection.
  Future<bool> checkConnection() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/ping'))
          .timeout(const Duration(seconds: 3));
          
      if (response.statusCode == 200) {
        _isConnected = true;
        return true;
      }
    } catch (e) {
      // Timeout or connection refused
    }
    _isConnected = false;
    return false;
  }

  /// Sends a detected waste item to the ESP32 dashboard.
  Future<bool> sendWasteData({
    required String label,
    required String binId,
    required String binName,
    required double confidence,
    required String direction,
    required double? distanceCm,
    required double coordX,
    required double coordY,
    required String gridCell,
    required int pixelX,
    required int pixelY,
  }) async {
    if (!_isConnected) return false;

    try {
      final payload = {
        'timestamp': DateTime.now().toIso8601String(),
        'label': label,
        'binId': binId,
        'binName': binName,
        'confidence': confidence,
        'direction': direction,
        'distanceCm': distanceCm ?? -1.0,
        'coordX': coordX,
        'coordY': coordY,
        'gridCell': gridCell,
        'pixelX': pixelX,
        'pixelY': pixelY,
      };

      final response = await http
          .post(
            Uri.parse('$baseUrl/data'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 2));

      return response.statusCode == 200;
    } catch (e) {
      // If we fail to send, we might have dropped off the hotspot
      _isConnected = false;
      return false;
    }
  }

  /// Sends a grid-based robotic arm command to the ESP32.
  ///
  /// The [command] map should contain `grid_x`, `grid_y`, `pixel_x`,
  /// `pixel_y`, and `action` keys (as produced by [RobotController]).
  Future<bool> sendRobotCommand(Map<String, dynamic> command) async {
    if (!_isConnected) return false;

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/command'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(command),
          )
          .timeout(const Duration(seconds: 2));

      return response.statusCode == 200;
    } catch (e) {
      _isConnected = false;
      return false;
    }
  }
}
