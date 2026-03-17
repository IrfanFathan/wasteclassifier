import 'dart:ui';

/// A single classification/detection result with its bounding box, class label,
/// and confidence.
///
/// For Teachable Machine classification, the [box] spans the entire frame
/// (since the model classifies the whole image, not individual objects).
class Detection {
  /// Bounding box in original camera frame pixel coordinates.
  /// For classification models, this is the full frame (0, 0, width, height).
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

/// Result of the preprocessing step.
///
/// Contains the normalized 224x224x3 float tensor for Teachable Machine
/// classification. The padLeft/padTop/scale fields are retained for API
/// compatibility but are always 0/0/1.0 for simple-resize preprocessing.
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
