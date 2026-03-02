/// waste_locator.dart
///
/// Provides spatial location estimates for detected waste objects.
///
/// Since the Teachable Machine TFLite model is a **classifier** (outputs class
/// probabilities only, not bounding boxes), this module uses a confidence-based
/// heuristic to estimate:
///
///   - **Direction** – which horizontal zone (LEFT / CENTER / RIGHT) the camera
///     should be steered toward so the robot aligns with the waste.
///
///   - **Distance** – an approximation based on detection confidence.
///     Higher confidence indicates the object fills more of the frame → closer.
///
///   - **Robot Command** – a simple text command derived from direction and
///     distance that can be relayed to the robot controller.
///
/// When this app is upgraded to a **detection model** that outputs bounding-box
/// coordinates, the [WasteLocator.compute] function can be swapped with the
/// true bounding-box centre-X and bbox-width values.
library;

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

  const WasteLocation({
    required this.direction,
    required this.estimatedDistanceCm,
    required this.robotCommand,
    required this.speedHint,
  });

  /// Returns a [WasteLocation] indicating no detection.
  static const unknown = WasteLocation(
    direction: WasteDirection.unknown,
    estimatedDistanceCm: null,
    robotCommand: 'SCANNING…',
    speedHint: 'stop',
  );
}

// ─── WasteLocator ─────────────────────────────────────────────────────────

/// Computes [WasteLocation] from detection inputs.
///
/// ### Parameters
///
/// - [confidence]        : Model probability of the detected waste class (0–1).
/// - [frameWidthFraction]: Normalised horizontal position of the object centre
///                         in the camera frame (0.0 = far left, 1.0 = far right).
///                         A value of **0.5** means the object is dead centre.
///                         Pass `0.5` when the position is unknown (full-frame
///                         classification mode).
/// - [minConfidence]     : Minimum confidence to trust the detection (default 0.6).
class WasteLocator {
  // ── Calibration constants ──────────────────────────────────────────────
  // These represent typical values for a mid-range phone camera at arm's length.
  // Adjust via calibration (see Task 4 calibration notes).

  /// Assumed average width of a waste object in centimetres.
  static const double knownWasteWidthCm = 15.0;

  /// Effective focal length in pixels (calibrated for a typical phone camera).
  /// For a 1080p-wide frame, a rough starting value is 800px.
  static const double focalLengthPx = 800.0;

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

  /// Computes the [WasteLocation] from a model's confidence output and an
  /// optional normalised horizontal position hint.
  ///
  /// ```dart
  /// final location = WasteLocator.compute(
  ///   confidence: 0.87,
  ///   frameWidthFraction: 0.3, // object is in the left zone
  /// );
  /// print(location.robotCommand); // "TURN LEFT"
  /// ```
  static WasteLocation compute({
    required double confidence,
    double frameWidthFraction = 0.5,
    double minConfidence = 0.6,
  }) {
    // Guard: too low confidence → no reliable location.
    if (confidence < minConfidence) return WasteLocation.unknown;

    // ── Determine horizontal direction ──────────────────────────────────
    final direction = _computeDirection(frameWidthFraction);

    // ── Estimate distance ───────────────────────────────────────────────
    // Use confidence as a proxy:
    //   • High confidence ≈ object fills more frame ≈ closer.
    //   • Formula: distance ≈ BASE_DISTANCE × (1 - confidence)
    //   • BASE_DISTANCE chosen so 100% confidence ≈ ~10 cm (arm length).
    final estimatedDistanceCm = _estimateDistance(confidence);

    // ── Robot command & speed ───────────────────────────────────────────
    final speedHint = _speedHint(confidence);
    final robotCommand = _robotCommand(direction, confidence);

    return WasteLocation(
      direction: direction,
      estimatedDistanceCm: estimatedDistanceCm,
      robotCommand: robotCommand,
      speedHint: speedHint,
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────

  /// Returns which zone [fraction] falls into based on frame thirds.
  static WasteDirection _computeDirection(double fraction) {
    if (fraction < leftBoundary) return WasteDirection.left;
    if (fraction > rightBoundary) return WasteDirection.right;
    return WasteDirection.center;
  }

  /// Maps detection confidence to a human-meaningful distance in centimetres.
  ///
  /// At 60% confidence the object is estimated at ~120 cm.
  /// At 95%+ it is effectively at the stop distance (~10 cm).
  static double _estimateDistance(double confidence) {
    // Clamp to [0.6, 1.0] before computing.
    final c = confidence.clamp(0.6, 1.0);
    // Linear interpolation: conf=0.6 → 120 cm, conf=1.0 → 10 cm.
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
    // If confidence is very high → time to stop and pick up.
    if (confidence >= stopThreshold) return 'STOP + PICK UP';

    return switch (direction) {
      WasteDirection.left   => 'TURN LEFT',
      WasteDirection.right  => 'TURN RIGHT',
      WasteDirection.center => 'GO STRAIGHT',
      WasteDirection.unknown => 'SCANNING…',
    };
  }
}
