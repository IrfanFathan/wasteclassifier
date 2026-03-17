import 'package:flutter_test/flutter_test.dart';
import 'package:wasteclassifier/services/nms_processor.dart';

// Helper: build a minimal rawOutput row from [cx, cy, w, h] + class scores.
List<double> _row(
  double cx,
  double cy,
  double w,
  double h,
  List<double> scores,
) {
  return [cx, cy, w, h, ...scores];
}

void main() {
  // Labels for a simple 3-class scenario (indices 0, 1, 2).
  const labels = ['plastic', 'metal', 'glass'];

  // Letterbox identity: no padding, scale = 1.0, 640×640 frame.
  const padLeft = 0;
  const padTop = 0;
  const scale = 1.0;
  const origW = 640;
  const origH = 640;

  // ─── Identical boxes ───────────────────────────────────────────────────────

  group('NmsProcessor — identical boxes', () {
    test('two identical high-confidence boxes → only one kept', () {
      final raw = [
        _row(320, 320, 100, 100, [0.0, 0.9, 0.0]), // metal, 0.9
        _row(320, 320, 100, 100, [0.0, 0.8, 0.0]), // metal, 0.8
      ];

      final results = NmsProcessor.process(
        rawOutput: raw,
        labels: labels,
        padLeft: padLeft,
        padTop: padTop,
        scale: scale,
        origWidth: origW,
        origHeight: origH,
        confidenceThreshold: 0.5,
        iouThreshold: 0.45,
      );

      expect(results.length, 1);
      expect(results.first.label, 'metal');
      expect(results.first.confidence, closeTo(0.9, 0.001));
    });
  });

  // ─── Overlapping same-class ────────────────────────────────────────────────

  group('NmsProcessor — overlapping same-class boxes', () {
    test(
      'two heavily overlapping same-class boxes → highest confidence kept',
      () {
        // Boxes largely overlapping (IoU >> 0.45)
        final raw = [
          _row(320, 320, 200, 200, [0.95, 0.0, 0.0]), // plastic, 0.95
          _row(330, 330, 200, 200, [0.70, 0.0, 0.0]), // plastic, 0.70
        ];

        final results = NmsProcessor.process(
          rawOutput: raw,
          labels: labels,
          padLeft: padLeft,
          padTop: padTop,
          scale: scale,
          origWidth: origW,
          origHeight: origH,
          confidenceThreshold: 0.5,
          iouThreshold: 0.45,
        );

        expect(results.length, 1);
        expect(results.first.label, 'plastic');
        expect(results.first.confidence, closeTo(0.95, 0.001));
      },
    );
  });

  // ─── Overlapping different-class ──────────────────────────────────────────

  group('NmsProcessor — overlapping different-class boxes', () {
    test('two heavily overlapping boxes of different classes → both kept', () {
      // NMS is per-class; different labels must not suppress each other.
      final raw = [
        _row(320, 320, 200, 200, [0.9, 0.0, 0.0]), // plastic
        _row(320, 320, 200, 200, [0.0, 0.9, 0.0]), // metal
      ];

      final results = NmsProcessor.process(
        rawOutput: raw,
        labels: labels,
        padLeft: padLeft,
        padTop: padTop,
        scale: scale,
        origWidth: origW,
        origHeight: origH,
        confidenceThreshold: 0.5,
        iouThreshold: 0.45,
      );

      expect(results.length, 2);
      final resultLabels = results.map((d) => d.label).toSet();
      expect(resultLabels, containsAll(['plastic', 'metal']));
    });
  });

  // ─── Letterbox coordinate unmapping ───────────────────────────────────────

  group('NmsProcessor — letterbox coordinate unmapping', () {
    test('box in padded region is unmapped correctly', () {
      // Simulate a letterbox where the image was scaled to 0.5 and padded
      // 80px on the left and 60px on top.
      //
      // A box at cx=320, cy=320 in 640×640 space with w=100, h=100 should
      // unmap to original coords:
      //   x1 = (320 - 50 - 80) / 0.5 = 380
      //   y1 = (320 - 50 - 60) / 0.5 = 420
      //   x2 = (320 + 50 - 80) / 0.5 = 580
      //   y2 = (320 + 50 - 60) / 0.5 = 620
      const testPadLeft = 80;
      const testPadTop = 60;
      const testScale = 0.5;
      const testOrigW = 1280;
      const testOrigH = 960;

      final raw = [
        _row(320, 320, 100, 100, [0.0, 0.0, 0.85]), // glass
      ];

      final results = NmsProcessor.process(
        rawOutput: raw,
        labels: labels,
        padLeft: testPadLeft,
        padTop: testPadTop,
        scale: testScale,
        origWidth: testOrigW,
        origHeight: testOrigH,
        confidenceThreshold: 0.5,
        iouThreshold: 0.45,
      );

      expect(results.length, 1);
      final box = results.first.box;
      expect(box.left, closeTo(380.0, 0.01));
      expect(box.top, closeTo(420.0, 0.01));
      expect(box.right, closeTo(580.0, 0.01));
      expect(box.bottom, closeTo(620.0, 0.01));
    });

    test('box coordinates are clamped to original frame bounds', () {
      // A box that extends past the frame edge after unmapping must be clamped.
      // With scale=1.0 and no padding, a box at x=600, w=100 → x2=650 → clamped to 640.
      final raw = [
        _row(600, 320, 100, 100, [0.8, 0.0, 0.0]),
      ];

      final results = NmsProcessor.process(
        rawOutput: raw,
        labels: labels,
        padLeft: 0,
        padTop: 0,
        scale: 1.0,
        origWidth: 640,
        origHeight: 640,
        confidenceThreshold: 0.5,
        iouThreshold: 0.45,
      );

      expect(results.length, 1);
      expect(results.first.box.right, lessThanOrEqualTo(640.0));
    });
  });

  // ─── Confidence filtering ─────────────────────────────────────────────────

  group('NmsProcessor — confidence filtering', () {
    test('detections below threshold are excluded', () {
      final raw = [
        _row(100, 100, 50, 50, [0.3, 0.0, 0.0]), // below 0.5 threshold
        _row(200, 200, 50, 50, [0.0, 0.8, 0.0]), // above threshold
      ];

      final results = NmsProcessor.process(
        rawOutput: raw,
        labels: labels,
        padLeft: 0,
        padTop: 0,
        scale: 1.0,
        origWidth: 640,
        origHeight: 640,
        confidenceThreshold: 0.5,
        iouThreshold: 0.45,
      );

      expect(results.length, 1);
      expect(results.first.label, 'metal');
    });

    test('empty raw output returns empty list', () {
      final results = NmsProcessor.process(
        rawOutput: [],
        labels: labels,
        padLeft: 0,
        padTop: 0,
        scale: 1.0,
        origWidth: 640,
        origHeight: 640,
      );
      expect(results, isEmpty);
    });
  });
}
