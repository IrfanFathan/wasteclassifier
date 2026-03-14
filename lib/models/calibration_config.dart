import 'dart:convert';
import 'dart:math';

/// Camera calibration and coordinate mapping configuration.
///
/// Supports two methods for converting pixel coordinates to real-world:
///
///   1. **Camera-height geometry** — uses camera height and focal length
///      to estimate distance on a ground plane (always available).
///
///   2. **Homography** — uses 4 reference point pairs to compute a 3×3
///      perspective transform matrix (optional, more accurate).
class CalibrationConfig {
  /// Camera height above the ground plane, in centimetres.
  final double cameraHeightCm;

  /// Effective focal length in pixels.
  /// For a 1080p phone camera, a reasonable default is ~800px.
  final double focalLengthPx;

  /// Frame width the calibration was computed for.
  final int imageWidth;

  /// Frame height the calibration was computed for.
  final int imageHeight;

  /// 4 pixel reference points: [[px1,py1], [px2,py2], [px3,py3], [px4,py4]].
  /// Null when homography is not configured.
  final List<List<double>>? imagePoints;

  /// 4 real-world reference points in cm: [[x1,y1], …].
  /// Null when homography is not configured.
  final List<List<double>>? realWorldPoints;

  /// Pre-computed 3×3 homography matrix (row-major, 9 elements).
  /// Null if [imagePoints] and [realWorldPoints] are not set.
  final List<double>? _homography;

  CalibrationConfig({
    this.cameraHeightCm = 150.0,
    this.focalLengthPx = 800.0,
    this.imageWidth = 1920,
    this.imageHeight = 1080,
    this.imagePoints,
    this.realWorldPoints,
  }) : _homography = (imagePoints != null && realWorldPoints != null)
            ? _computeHomography(imagePoints, realWorldPoints)
            : null;

  /// Whether a homography matrix is available for coordinate mapping.
  bool get hasHomography => _homography != null;

  // ─── Pixel → Real-World Coordinate Mapping ────────────────────────────

  /// Converts pixel coordinates ([px], [py]) to real-world coordinates
  /// in centimetres using the homography matrix.
  ///
  /// Returns `null` if homography is not configured.
  ({double x, double y})? pixelToRealWorld(double px, double py) {
    final h = _homography;
    if (h == null) return null;

    // Apply H: [x', y', w'] = H × [px, py, 1]
    final double xp = h[0] * px + h[1] * py + h[2];
    final double yp = h[3] * px + h[4] * py + h[5];
    final double wp = h[6] * px + h[7] * py + h[8];

    if (wp.abs() < 1e-10) return null;

    return (x: xp / wp, y: yp / wp);
  }

  /// Estimates the distance to an object at pixel row [cy] using
  /// camera-height geometry (similar triangles).
  ///
  /// Returns distance in centimetres. Returns `null` if the object is
  /// at or above the horizon line.
  double? estimateDistanceByCameraHeight(int cy) {
    final double imageCenterY = imageHeight / 2.0;
    final double pixelOffset = cy - imageCenterY;

    // Object at or above the horizon → infinite distance.
    if (pixelOffset <= 0) return null;

    final distance = (focalLengthPx * cameraHeightCm) / pixelOffset;
    return distance.abs();
  }

  /// Estimates distance using Euclidean distance from the real-world
  /// coordinates (if homography is available), or falls back to
  /// camera-height geometry.
  double? estimateDistance(int cx, int cy) {
    // Try homography first.
    final realWorld = pixelToRealWorld(cx.toDouble(), cy.toDouble());
    if (realWorld != null) {
      return sqrt(realWorld.x * realWorld.x + realWorld.y * realWorld.y);
    }

    // Fall back to camera-height geometry.
    return estimateDistanceByCameraHeight(cy);
  }

  // ─── Serialisation ────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'cameraHeightCm': cameraHeightCm,
        'focalLengthPx': focalLengthPx,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
        if (imagePoints != null) 'imagePoints': imagePoints,
        if (realWorldPoints != null) 'realWorldPoints': realWorldPoints,
      };

  factory CalibrationConfig.fromJson(Map<String, dynamic> json) {
    return CalibrationConfig(
      cameraHeightCm: (json['cameraHeightCm'] as num?)?.toDouble() ?? 150.0,
      focalLengthPx: (json['focalLengthPx'] as num?)?.toDouble() ?? 800.0,
      imageWidth: (json['imageWidth'] as num?)?.toInt() ?? 1920,
      imageHeight: (json['imageHeight'] as num?)?.toInt() ?? 1080,
      imagePoints: json['imagePoints'] != null
          ? (json['imagePoints'] as List)
              .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
              .toList()
          : null,
      realWorldPoints: json['realWorldPoints'] != null
          ? (json['realWorldPoints'] as List)
              .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
              .toList()
          : null,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory CalibrationConfig.fromJsonString(String s) =>
      CalibrationConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);

  // ─── Homography Computation ───────────────────────────────────────────

  /// Computes a 3×3 homography matrix from 4 point correspondences using
  /// the Direct Linear Transform (DLT) approach.
  ///
  /// Returns a 9-element list (row-major 3×3 matrix), or null on failure.
  static List<double>? _computeHomography(
    List<List<double>> imgPts,
    List<List<double>> realPts,
  ) {
    if (imgPts.length != 4 || realPts.length != 4) return null;

    // Build the 8×9 matrix A for Ah = 0.
    final List<List<double>> a = [];
    for (int i = 0; i < 4; i++) {
      final double sx = imgPts[i][0];
      final double sy = imgPts[i][1];
      final double dx = realPts[i][0];
      final double dy = realPts[i][1];

      a.add([
        -sx, -sy, -1, 0, 0, 0, sx * dx, sy * dx, dx,
      ]);
      a.add([
        0, 0, 0, -sx, -sy, -1, sx * dy, sy * dy, dy,
      ]);
    }

    // Solve using a simplified approach: since we have exactly 8 equations
    // and 9 unknowns, fix h[8] = 1 and solve the 8×8 system.
    final List<List<double>> m = List.generate(8, (i) => List<double>.filled(9, 0.0));
    for (int i = 0; i < 8; i++) {
      for (int j = 0; j < 9; j++) {
        m[i][j] = a[i][j];
      }
    }

    // Move the last column to the right-hand side (h[8] = 1).
    final List<double> rhs = List.generate(8, (i) => -m[i][8]);
    final List<List<double>> lhs = List.generate(
      8,
      (i) => m[i].sublist(0, 8),
    );

    // Gaussian elimination with partial pivoting.
    final h = _solveLinearSystem(lhs, rhs);
    if (h == null) return null;

    return [...h, 1.0];
  }

  /// Solves an n×n linear system Ax = b using Gaussian elimination
  /// with partial pivoting.
  static List<double>? _solveLinearSystem(
    List<List<double>> a,
    List<double> b,
  ) {
    final int n = b.length;

    // Augmented matrix.
    final aug = List.generate(
      n,
      (i) => [...a[i], b[i]],
    );

    for (int col = 0; col < n; col++) {
      // Find pivot.
      int maxRow = col;
      double maxVal = aug[col][col].abs();
      for (int row = col + 1; row < n; row++) {
        if (aug[row][col].abs() > maxVal) {
          maxVal = aug[row][col].abs();
          maxRow = row;
        }
      }
      if (maxVal < 1e-12) return null; // Singular.

      // Swap rows.
      final tmp = aug[col];
      aug[col] = aug[maxRow];
      aug[maxRow] = tmp;

      // Eliminate.
      for (int row = col + 1; row < n; row++) {
        final factor = aug[row][col] / aug[col][col];
        for (int j = col; j <= n; j++) {
          aug[row][j] -= factor * aug[col][j];
        }
      }
    }

    // Back substitution.
    final x = List<double>.filled(n, 0.0);
    for (int i = n - 1; i >= 0; i--) {
      double sum = aug[i][n];
      for (int j = i + 1; j < n; j++) {
        sum -= aug[i][j] * x[j];
      }
      x[i] = sum / aug[i][i];
    }

    return x;
  }
}
