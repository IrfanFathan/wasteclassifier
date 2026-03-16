import 'dart:collection';
import 'dart:math';
import 'dart:ui';

import '../models/detection.dart';
import '../utils/detection_constants.dart';

/// Temporal smoother that averages detections across a rolling window of frames.
///
/// Reduces bounding box jitter and filters out false positives by requiring
/// detections to appear in at least [kSmootherMinAppearances] of the last
/// [kSmootherWindowSize] frames.
class DetectionSmoother {
  final int windowSize;
  final double matchIouThreshold;
  final int minAppearances;
  final Queue<List<Detection>> _history = Queue();

  DetectionSmoother({
    this.windowSize = kSmootherWindowSize,
    this.matchIouThreshold = kSmootherMatchIou,
    this.minAppearances = kSmootherMinAppearances,
  });

  /// Adds the latest frame's detections and returns temporally smoothed results.
  List<Detection> smooth(List<Detection> current) {
    _history.addLast(current);
    if (_history.length > windowSize) _history.removeFirst();

    // Group detections across frames by IoU + label matching.
    final Map<String, List<Detection>> groups = {};

    for (final frame in _history) {
      for (final det in frame) {
        final key = _findMatchingKey(groups, det);
        groups.putIfAbsent(key, () => []).add(det);
      }
    }

    return groups.values
        .where((group) => group.length >= minAppearances)
        .map(_average)
        .toList();
  }

  /// Resets the history buffer (e.g. when the camera resumes).
  void reset() {
    _history.clear();
  }

  Detection _average(List<Detection> group) {
    final avgLeft =
        group.map((d) => d.box.left).reduce((a, b) => a + b) / group.length;
    final avgTop =
        group.map((d) => d.box.top).reduce((a, b) => a + b) / group.length;
    final avgRight =
        group.map((d) => d.box.right).reduce((a, b) => a + b) / group.length;
    final avgBottom =
        group.map((d) => d.box.bottom).reduce((a, b) => a + b) / group.length;
    final avgConf =
        group.map((d) => d.confidence).reduce((a, b) => a + b) / group.length;

    return Detection(
      box: Rect.fromLTRB(avgLeft, avgTop, avgRight, avgBottom),
      label: group.first.label,
      confidence: avgConf,
    );
  }

  String _findMatchingKey(Map<String, List<Detection>> groups, Detection det) {
    for (final entry in groups.entries) {
      if (entry.value.isNotEmpty &&
          entry.value.last.label == det.label &&
          _iou(entry.value.last.box, det.box) > matchIouThreshold) {
        return entry.key;
      }
    }
    return '${det.label}_${groups.length}';
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
