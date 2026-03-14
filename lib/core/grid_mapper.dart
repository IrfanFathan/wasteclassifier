/// grid_mapper.dart
///
/// Converts pixel coordinates from object detection into a center-origin
/// 8×8 Cartesian grid coordinate system for robotic arm pick-and-place.
///
/// The camera frame center is the origin (0,0).
///   - Positive X → right
///   - Negative X → left
///   - Positive Y → up
///   - Negative Y → down
library;

// ─── GridPosition Model ───────────────────────────────────────────────────

/// Holds the full spatial output for a detected object in the grid system.
class GridPosition {
  /// Grid column index (center-origin). Positive = right, negative = left.
  final int gridX;

  /// Grid row index (center-origin). Positive = up, negative = down.
  final int gridY;

  /// Raw pixel X coordinate of the object center in the original frame.
  final int pixelX;

  /// Raw pixel Y coordinate of the object center in the original frame.
  final int pixelY;

  /// Center-based Cartesian X coordinate (pixels from center).
  final double centerX;

  /// Center-based Cartesian Y coordinate (pixels from center).
  final double centerY;

  /// Robotic action to perform. Defaults to `"pick"`.
  final String action;

  const GridPosition({
    required this.gridX,
    required this.gridY,
    required this.pixelX,
    required this.pixelY,
    required this.centerX,
    required this.centerY,
    this.action = 'pick',
  });

  /// Human-readable grid label, e.g. "(1, 0)".
  String get label => '($gridX, $gridY)';

  /// Serialises to JSON for ESP32 transmission.
  Map<String, dynamic> toJson() => {
    'grid_x': gridX,
    'grid_y': gridY,
    'pixel_x': pixelX,
    'pixel_y': pixelY,
    'action': action,
  };

  @override
  String toString() => 'GridPosition$label';
}

// ─── GridMapper ───────────────────────────────────────────────────────────

/// Pure-logic utility for mapping pixel coordinates to an 8×8 center-origin
/// Cartesian grid.
class GridMapper {
  // ── Constants ──────────────────────────────────────────────────────────

  /// Fixed processing resolution width.
  static const int imageWidth = 640;

  /// Fixed processing resolution height.
  static const int imageHeight = 640;

  /// Number of grid rows.
  static const int gridRows = 8;

  /// Number of grid columns.
  static const int gridColumns = 8;

  /// Width of each grid cell in pixels.
  static const double cellWidth = imageWidth / gridColumns; // 80

  /// Height of each grid cell in pixels.
  static const double cellHeight = imageHeight / gridRows; // 80

  /// X coordinate of the frame center.
  static const double frameCenterX = imageWidth / 2; // 320

  /// Y coordinate of the frame center.
  static const double frameCenterY = imageHeight / 2; // 320

  // ── Public API ─────────────────────────────────────────────────────────

  /// Calculates the center point of a detected object from its bounding box.
  ///
  /// Returns `(objectCenterX, objectCenterY)` in pixel coordinates.
  static ({double x, double y}) calculateObjectCenter({
    required double xMin,
    required double yMin,
    required double xMax,
    required double yMax,
  }) {
    return (x: (xMin + xMax) / 2, y: (yMin + yMax) / 2);
  }

  /// Converts pixel coordinates (top-left origin) to center-based Cartesian
  /// coordinates where the frame center is (0, 0).
  ///
  /// - Positive X → right of center
  /// - Positive Y → above center
  static ({double x, double y}) convertToCenterCoordinates(
    double pixelX,
    double pixelY,
  ) {
    return (x: pixelX - frameCenterX, y: frameCenterY - pixelY);
  }

  /// Determines the grid cell for a set of center-based coordinates.
  ///
  /// Uses `floor()` to map continuous coordinates to discrete grid cells.
  static ({int gridX, int gridY}) computeGridCell(
    double centerX,
    double centerY,
  ) {
    return (
      gridX: (centerX / cellWidth).floor(),
      gridY: (centerY / cellHeight).floor(),
    );
  }

  /// Full pipeline: bounding box → [GridPosition].
  ///
  /// Takes bounding box coordinates directly from the detection model and
  /// returns a fully populated [GridPosition].
  ///
  /// [frameWidth] and [frameHeight] should match the actual camera frame
  /// dimensions. Defaults to 640×640 if not provided.
  static GridPosition fromBoundingBox({
    required double xMin,
    required double yMin,
    required double xMax,
    required double yMax,
    String action = 'pick',
    int frameWidth = imageWidth,
    int frameHeight = imageHeight,
  }) {
    final center = calculateObjectCenter(
      xMin: xMin,
      yMin: yMin,
      xMax: xMax,
      yMax: yMax,
    );
    return fromPixel(
      pixelX: center.x,
      pixelY: center.y,
      action: action,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
    );
  }

  /// Converts a single pixel coordinate to a [GridPosition].
  ///
  /// Use this when you already have the object center pixel (e.g. from the
  /// existing detection pipeline which computes `cx`, `cy`).
  ///
  /// [frameWidth] and [frameHeight] should match the actual camera frame
  /// dimensions. Defaults to 640×640 if not provided.
  static GridPosition fromPixel({
    required double pixelX,
    required double pixelY,
    String action = 'pick',
    int frameWidth = imageWidth,
    int frameHeight = imageHeight,
  }) {
    final double centerX = pixelX - frameWidth / 2;
    final double centerY = frameHeight / 2 - pixelY;
    final int gridX = (centerX / (frameWidth / gridColumns)).floor();
    final int gridY = (centerY / (frameHeight / gridRows)).floor();

    return GridPosition(
      gridX: gridX,
      gridY: gridY,
      pixelX: pixelX.round(),
      pixelY: pixelY.round(),
      centerX: centerX,
      centerY: centerY,
      action: action,
    );
  }
}
