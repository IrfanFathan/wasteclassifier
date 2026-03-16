import 'dart:ui';

/// A single detected object with its bounding box, class label, and confidence.
class Detection {
  /// Bounding box in original camera frame pixel coordinates.
  final Rect box;

  /// Class label (e.g. "aerosol_can", "spoon").
  final String label;

  /// Combined confidence score (objectness x class probability).
  final double confidence;

  const Detection({
    required this.box,
    required this.label,
    required this.confidence,
  });

  @override
  String toString() =>
      'Detection("$label", ${(confidence * 100).toStringAsFixed(1)}%, '
      'box=${box.left.toStringAsFixed(0)},${box.top.toStringAsFixed(0)}'
      '-${box.right.toStringAsFixed(0)},${box.bottom.toStringAsFixed(0)})';
}

/// Result of the OpenCV preprocessing step.
///
/// Contains the normalized 640x640x3 float tensor plus the letterbox
/// metadata needed to unmap detection coordinates back to the original frame.
class PreprocessResult {
  /// Normalized float32 tensor of shape [640, 640, 3].
  final List<double> floatData;

  /// Pixels padded on the left during letterbox resize.
  final int padLeft;

  /// Pixels padded on the top during letterbox resize.
  final int padTop;

  /// Scale factor applied during letterbox resize.
  final double scale;

  const PreprocessResult({
    required this.floatData,
    required this.padLeft,
    required this.padTop,
    required this.scale,
  });
}
