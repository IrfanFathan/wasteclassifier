/// waste_locator.dart
///
/// Provides spatial location estimates for detected waste objects.
///
/// Combines pixel-level coordinates from the waste detector with
/// calibration-based distance estimation and robot navigation commands.
library;

import '../models/calibration_config.dart';

// ─── Direction Enum ────────────────────────────────────────────────────────

/// Represents which horizontal zone of the camera frame the waste is in.
enum WasteDirection {
  /// Waste is in the left third of the frame.
  left,

  /// Waste is in the centre third of the frame (robot goes straight).
  center,

  /// Waste is in the right third of the frame.
  right,

  /// Direction is not yet determined (no object detected).
  unknown,
}

// ─── WasteLocation Model ───────────────────────────────────────────────────

/// Holds all spatial output for a single detection frame.
class WasteLocation {
  /// Which horizontal zone the waste occupies.
  final WasteDirection direction;

  /// Estimated distance in centimetres. May be null if confidence is too low.
  final double? estimatedDistanceCm;

  /// Human-readable robot navigation command.
  final String robotCommand;

  /// Category speed hint for the robot: 'fast', 'slow', or 'stop'.
  final String speedHint;

  /// Normalised X position in the frame (0.0 = left edge, 1.0 = right edge).
  final double normX;

  /// Normalised Y position in the frame (0.0 = top edge, 1.0 = bottom edge).
  final double normY;

  /// Raw pixel X coordinate of the waste centre.
  final int pixelX;

  /// Raw pixel Y coordinate of the waste centre.
  final int pixelY;

  /// Real-world X coordinate in cm (from homography). Null if not calibrated.
  final double? realWorldX;

  /// Real-world Y coordinate in cm (from homography). Null if not calibrated.
  final double? realWorldY;

  const WasteLocation({
    required this.direction,
    required this.estimatedDistanceCm,
    required this.robotCommand,
    required this.speedHint,
    required this.normX,
    required this.normY,
    required this.pixelX,
    required this.pixelY,
    this.realWorldX,
    this.realWorldY,
  });

  /// Returns a [WasteLocation] indicating no detection.
  static const unknown = WasteLocation(
    direction: WasteDirection.unknown,
    estimatedDistanceCm: null,
    robotCommand: 'SCANNING…',
    speedHint: 'stop',
    normX: 0.0,
    normY: 0.0,
    pixelX: 0,
    pixelY: 0,
  );
}

// ─── WasteLocator ─────────────────────────────────────────────────────────

/// Computes [WasteLocation] from pixel coordinates and classification output.
class WasteLocator {
  // ── Thresholds ─────────────────────────────────────────────────────────

  /// If confidence exceeds this threshold the object is considered "very close"
  /// (i.e., essentially filling the frame) → STOP + PICK UP.
  static const double stopThreshold = 0.95;

  /// If confidence is above this the robot slows down.
  static const double slowThreshold = 0.80;

  /// Left zone boundary: frame fraction below this is LEFT.
  static const double leftBoundary = 0.35;

  /// Right zone boundary: frame fraction above this is RIGHT.
  static const double rightBoundary = 0.65;

  // ── Public API ─────────────────────────────────────────────────────────

  /// Computes the [WasteLocation] from pixel coordinates and confidence.
  ///
  /// [pixelX], [pixelY] — raw pixel centre of the detected object.
  /// [frameWidth], [frameHeight] — dimensions of the camera frame.
  /// [confidence] — model probability of the detected waste class (0–1).
  /// [calibration] — optional camera calibration for distance/real-world coords.
  /// [minConfidence] — minimum confidence to trust the detection (default 0.6).
  static WasteLocation compute({
    required int pixelX,
    required int pixelY,
    required int frameWidth,
    required int frameHeight,
    required double confidence,
    CalibrationConfig? calibration,
    double minConfidence = 0.6,
  }) {
    // Guard: too low confidence → no reliable location.
    if (confidence < minConfidence) return WasteLocation.unknown;

    // ── Normalised coordinates ──────────────────────────────────────────
    final double normX = pixelX / frameWidth;
    final double normY = pixelY / frameHeight;

    // ── Determine horizontal direction ──────────────────────────────────
    final direction = _computeDirection(normX);

    // ── Estimate distance ───────────────────────────────────────────────
    double? estimatedDistanceCm;
    double? realWorldX;
    double? realWorldY;

    if (calibration != null) {
      // Use calibration — homography or camera-height geometry.
      estimatedDistanceCm = calibration.estimateDistance(pixelX, pixelY);

      // Try homography for real-world coordinates.
      final realWorld = calibration.pixelToRealWorld(
        pixelX.toDouble(),
        pixelY.toDouble(),
      );
      if (realWorld != null) {
        realWorldX = double.parse(realWorld.x.toStringAsFixed(1));
        realWorldY = double.parse(realWorld.y.toStringAsFixed(1));
      }

      estimatedDistanceCm = estimatedDistanceCm != null
          ? double.parse(estimatedDistanceCm.toStringAsFixed(1))
          : null;
    } else {
      // Fallback: confidence-based heuristic.
      estimatedDistanceCm = _estimateDistanceByConfidence(confidence);
    }

    // ── Robot command & speed ───────────────────────────────────────────
    final speedHint = _speedHint(confidence);
    final robotCommand = _robotCommand(direction, confidence);

    return WasteLocation(
      direction: direction,
      estimatedDistanceCm: estimatedDistanceCm,
      robotCommand: robotCommand,
      speedHint: speedHint,
      normX: normX,
      normY: normY,
      pixelX: pixelX,
      pixelY: pixelY,
      realWorldX: realWorldX,
      realWorldY: realWorldY,
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────

  /// Returns which zone [fraction] falls into based on frame thirds.
  static WasteDirection _computeDirection(double fraction) {
    if (fraction < leftBoundary) return WasteDirection.left;
    if (fraction > rightBoundary) return WasteDirection.right;
    return WasteDirection.center;
  }

  /// Confidence-based distance heuristic (fallback when no calibration).
  ///
  /// At 60% confidence the object is estimated at ~120 cm.
  /// At 95%+ it is effectively at the stop distance (~10 cm).
  static double _estimateDistanceByConfidence(double confidence) {
    final c = confidence.clamp(0.6, 1.0);
    const double maxDist = 120.0;
    const double minDist = 10.0;
    final dist = maxDist - (maxDist - minDist) * ((c - 0.6) / 0.4);
    return double.parse(dist.toStringAsFixed(1));
  }

  /// Returns a speed hint for the robot based on proximity.
  static String _speedHint(double confidence) {
    if (confidence >= stopThreshold) return 'stop';
    if (confidence >= slowThreshold) return 'slow';
    return 'fast';
  }

  /// Produces the final text command string for the robot.
  static String _robotCommand(WasteDirection direction, double confidence) {
    if (confidence >= stopThreshold) return 'STOP + PICK UP';

    return switch (direction) {
      WasteDirection.left   => 'TURN LEFT',
      WasteDirection.right  => 'TURN RIGHT',
      WasteDirection.center => 'GO STRAIGHT',
      WasteDirection.unknown => 'SCANNING…',
    };
  }
}
