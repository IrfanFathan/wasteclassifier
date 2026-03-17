// dart_preprocessor.dart
//
// Pure-Dart fallback for the preprocessing pipeline.
//
// Used when the native libyolo_preprocess.so is unavailable (e.g. OpenCV SDK
// not configured, first build, or unsupported device ABI).
//
// Teachable Machine models expect:
//   - Input: [1, 224, 224, 3] NHWC, float32, normalised to [0, 1].
//   - Simple resize (no letterbox padding).
//
// The heavy work (YUV conversion + resize) runs inside a [compute] isolate so
// the platform UI thread is never blocked.

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/detection.dart';
import '../utils/detection_constants.dart';

// ─── Isolate message types ────────────────────────────────────────────────────

/// Parameters passed into the [compute] isolate.
typedef _PreprocessMsg = ({
  Uint8List yBytes,
  Uint8List uBytes,
  Uint8List vBytes,
  int yRowStride,
  int uvRowStride,
  int uvPixelStride,
  int frameWidth,
  int frameHeight,
  int targetSize,
});

/// Result returned from the [compute] isolate.
class _PreprocessResult {
  final Float32List floatData;
  final int padLeft;
  final int padTop;
  final double scale;

  const _PreprocessResult({
    required this.floatData,
    required this.padLeft,
    required this.padTop,
    required this.scale,
  });
}

// ─── Isolate entry point ─────────────────────────────────────────────────────

/// Top-level function required by [compute] — must not be a closure.
_PreprocessResult _runPreprocess(_PreprocessMsg msg) {
  // Step 1: YUV420 → RGB
  final rgb = img.Image(width: msg.frameWidth, height: msg.frameHeight);

  for (int py = 0; py < msg.frameHeight; py++) {
    for (int px = 0; px < msg.frameWidth; px++) {
      final yIdx = py * msg.yRowStride + px;
      final uvIdx = (py ~/ 2) * msg.uvRowStride + (px ~/ 2) * msg.uvPixelStride;

      final yVal = msg.yBytes[yIdx] & 0xFF;
      final uVal = msg.uBytes[uvIdx] & 0xFF;
      final vVal = msg.vBytes[uvIdx] & 0xFF;

      final r = (yVal + 1.402 * (vVal - 128)).round().clamp(0, 255);
      final g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128))
          .round()
          .clamp(0, 255);
      final b = (yVal + 1.772 * (uVal - 128)).round().clamp(0, 255);

      rgb.setPixelRgb(px, py, r, g, b);
    }
  }

  // Step 2: Simple resize to targetSize × targetSize (no letterbox).
  // Teachable Machine models are trained on resized (not letterboxed) images.
  final ts = msg.targetSize;
  final resized = img.copyResize(rgb, width: ts, height: ts);

  // Compute effective scale for coordinate unmapping (use the larger
  // dimension so that unmapping from the classification result works).
  final scaleX = ts / msg.frameWidth;
  final scaleY = ts / msg.frameHeight;
  final scale = (scaleX < scaleY) ? scaleX : scaleY;

  // Step 3: Normalise to Float32 [0, 1] in NHWC order.
  final floatData = Float32List(ts * ts * 3);
  int idx = 0;
  for (int r = 0; r < ts; r++) {
    for (int c = 0; c < ts; c++) {
      final pixel = resized.getPixel(c, r);
      floatData[idx++] = pixel.r / 255.0;
      floatData[idx++] = pixel.g / 255.0;
      floatData[idx++] = pixel.b / 255.0;
    }
  }

  return _PreprocessResult(
    floatData: floatData,
    padLeft: 0, // no letterbox padding for TM
    padTop: 0,
    scale: scale,
  );
}

// ─── Public API ───────────────────────────────────────────────────────────────

/// Pure-Dart preprocessing fallback.
///
/// Converts [image] (YUV420) → resized 224×224 Float32 tensor normalised
/// to [0, 1] in NHWC layout. Suitable for Teachable Machine TFLite models.
///
/// Runs in a worker isolate via [compute] — never blocks the UI thread.
///
/// Returns a [PreprocessResult] on success, or `null` if the isolate fails.
class DartPreprocessor {
  /// Preprocesses [image] using the pure-Dart pipeline.
  static Future<PreprocessResult?> preprocessFrame(CameraImage image) async {
    try {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final msg = (
        yBytes: yPlane.bytes,
        uBytes: uPlane.bytes,
        vBytes: vPlane.bytes,
        yRowStride: yPlane.bytesPerRow,
        uvRowStride: uPlane.bytesPerRow,
        uvPixelStride: uPlane.bytesPerPixel ?? 1,
        frameWidth: image.width,
        frameHeight: image.height,
        targetSize: kInputSize,
      );

      final result = await compute(_runPreprocess, msg);

      return PreprocessResult(
        floatData: result.floatData,
        padLeft: result.padLeft,
        padTop: result.padTop,
        scale: result.scale,
      );
    } catch (e) {
      debugPrint('[DartPreprocessor] preprocessFrame failed: $e');
      return null;
    }
  }
}
