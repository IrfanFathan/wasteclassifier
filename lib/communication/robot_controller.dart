/// robot_controller.dart
///
/// Creates structured commands from grid positions and sends them to the
/// ESP32 robotic arm controller via HTTP.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/grid_mapper.dart';
import '../services/esp32_service.dart';

/// Builds and transmits pick-and-place commands for the robotic arm.
class RobotController {
  RobotController._();

  // ── Command Creation ───────────────────────────────────────────────────

  /// Creates a JSON-ready command map from a [GridPosition].
  ///
  /// Example output:
  /// ```json
  /// {
  ///   "grid_x": 1,
  ///   "grid_y": 0,
  ///   "pixel_x": 400,
  ///   "pixel_y": 250,
  ///   "action": "pick"
  /// }
  /// ```
  static Map<String, dynamic> createRobotCommand(GridPosition position) {
    return {
      "object_detected": true,
      "coordinates": {
        "x": position.centerX.round(),
        "y": position.centerY.round()
      }
    };
  }
  // ── Transmission ───────────────────────────────────────────────────────

  /// Sends a grid command to the ESP32 via HTTP POST.
  ///
  /// Returns `true` if the ESP32 acknowledged the command (HTTP 200).
  /// Returns `false` on any error or if not connected.
  static Future<bool> sendCommandToESP32(
    Map<String, dynamic> command, {
    String? baseUrl,
  }) async {
    final url = baseUrl ?? Esp32Service.baseUrl;

    try {
      final response = await http
          .post(
            Uri.parse('$url/command'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(command),
          )
          .timeout(const Duration(seconds: 2));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Convenience: creates a command from [position] and sends it.
  static Future<bool> sendGridPosition(GridPosition position) async {
    final command = createRobotCommand(position);
    return sendCommandToESP32(command);
  }
}
