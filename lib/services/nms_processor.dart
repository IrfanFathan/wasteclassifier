import 'dart:math';
import 'dart:ui';

import '../models/detection.dart';
import '../utils/detection_constants.dart';

/// Processes raw YOLO model output into a filtered list of [Detection] objects.
///
/// Steps:
///   1. Confidence + class score filtering.
///   2. [cx, cy, w, h] -> [x1, y1, x2, y2] conversion.
///   3. Non-maximum suppression (NMS).
///   4. Letterbox coordinate unmapping back to original frame dimensions.
class NmsProcessor {
  /// Processes raw YOLO output tensor into final detections.
  ///
  /// [rawOutput]  — The model output of shape [1, numPredictions, numClasses + 4].
  ///                YOLO11n outputs [1, 8400, 85] for 80-class COCO, but the
  ///                actual number of classes is determined by [labels].length.
  /// [labels]     — Class label strings matching the model's class indices.
  /// [padLeft], [padTop], [scale] — Letterbox metadata from preprocessing.
  /// [origWidth], [origHeight]    — Original camera frame dimensions.
  /// [confidenceThreshold]        — Minimum combined score to keep a detection.
  /// [iouThreshold]               — IoU threshold for NMS suppression.
  static List<Detection> process({
    required List<List<double>> rawOutput,
    required List<String> labels,
    required int padLeft,
    required int padTop,
    required double scale,
    required int origWidth,
    required int origHeight,
    double confidenceThreshold = kConfidenceThreshold,
    double iouThreshold = kNmsIouThreshold,
  }) {
    final numClasses = labels.length;
    // YOLO11n output is transposed: [1, 84, 8400] where 84 = 4 + 80 classes.
    // After reshaping in Dart the rawOutput is [8400][84].
    // Columns 0-3: cx, cy, w, h (in pixels relative to 640x640).
    // Columns 4..(4+numClasses-1): class probabilities.

    final candidates = <Detection>[];

    for (final row in rawOutput) {
      if (row.length < 4 + numClasses) continue;

      // Find best class
      int bestClassIdx = 0;
      double bestClassScore = 0.0;
      for (int c = 0; c < numClasses; c++) {
        final score = row[4 + c];
        if (score > bestClassScore) {
          bestClassScore = score;
          bestClassIdx = c;
        }
      }

      // YOLO11n has no separate objectness — class scores ARE the confidences.
      final finalScore = bestClassScore;

      if (finalScore < confidenceThreshold) continue;

      // Convert [cx, cy, w, h] -> [x1, y1, x2, y2] in 640x640 space
      final cx = row[0];
      final cy = row[1];
      final w = row[2];
      final h = row[3];

      final x1 = cx - w / 2;
      final y1 = cy - h / 2;
      final x2 = cx + w / 2;
      final y2 = cy + h / 2;

      // Unmap from letterbox coordinates to original frame coordinates
      final unmappedX1 = (x1 - padLeft) / scale;
      final unmappedY1 = (y1 - padTop) / scale;
      final unmappedX2 = (x2 - padLeft) / scale;
      final unmappedY2 = (y2 - padTop) / scale;

      // Clamp to frame bounds
      final clampedX1 = unmappedX1.clamp(0.0, origWidth.toDouble());
      final clampedY1 = unmappedY1.clamp(0.0, origHeight.toDouble());
      final clampedX2 = unmappedX2.clamp(0.0, origWidth.toDouble());
      final clampedY2 = unmappedY2.clamp(0.0, origHeight.toDouble());

      if (clampedX2 <= clampedX1 || clampedY2 <= clampedY1) continue;

      candidates.add(Detection(
        box: Rect.fromLTRB(clampedX1, clampedY1, clampedX2, clampedY2),
        label: bestClassIdx < labels.length ? labels[bestClassIdx] : 'Unknown',
        confidence: finalScore,
      ));
    }

    return _applyNMS(candidates, iouThreshold: iouThreshold);
  }

  /// Applies greedy NMS: sort by confidence, suppress overlapping same-class boxes.
  static List<Detection> _applyNMS(
    List<Detection> detections, {
    double iouThreshold = kNmsIouThreshold,
  }) {
    detections.sort((a, b) => b.confidence.compareTo(a.confidence));

    final kept = <Detection>[];
    final suppressed = List<bool>.filled(detections.length, false);

    for (int i = 0; i < detections.length; i++) {
      if (suppressed[i]) continue;
      kept.add(detections[i]);
      for (int j = i + 1; j < detections.length; j++) {
        if (suppressed[j]) continue;
        if (detections[i].label == detections[j].label) {
          if (_iou(detections[i].box, detections[j].box) > iouThreshold) {
            suppressed[j] = true;
          }
        }
      }
    }
    return kept;
  }

  static double _iou(Rect a, Rect b) {
    final intersectLeft = max(a.left, b.left);
    final intersectTop = max(a.top, b.top);
    final intersectRight = min(a.right, b.right);
    final intersectBottom = min(a.bottom, b.bottom);

    if (intersectRight <= intersectLeft || intersectBottom <= intersectTop) {
      return 0.0;
    }

    final intersectArea =
        (intersectRight - intersectLeft) * (intersectBottom - intersectTop);
    final aArea = a.width * a.height;
    final bArea = b.width * b.height;
    return intersectArea / (aArea + bArea - intersectArea);
  }
}
