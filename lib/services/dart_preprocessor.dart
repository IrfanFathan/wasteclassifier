// dart_preprocessor.dart
//
// Pure-Dart fallback for the OpenCV preprocessing pipeline.
//
// Used when the native libyolo_preprocess.so is unavailable (e.g. OpenCV SDK
// not configured, first build, or unsupported device ABI).
//
// Differences vs. the native path:
//   - No blur / Laplacian variance check (every frame is processed).
//   - No CLAHE lighting normalisation.
//   - Letterbox resize uses the `image` package (slower than OpenCV but correct).
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

  // Step 2: Letterbox resize to targetSize × targetSize
  final ts = msg.targetSize;
  final scale = (ts / msg.frameWidth) < (ts / msg.frameHeight)
      ? ts / msg.frameWidth
      : ts / msg.frameHeight;

  final newW = (msg.frameWidth * scale).round();
  final newH = (msg.frameHeight * scale).round();

  final resized = img.copyResize(rgb, width: newW, height: newH);

  final padLeft = (ts - newW) ~/ 2;
  final padTop = (ts - newH) ~/ 2;

  // Fill canvas with gray (114) and paste the resized image.
  final canvas = img.Image(width: ts, height: ts);
  img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
  img.compositeImage(canvas, resized, dstX: padLeft, dstY: padTop);

  // Step 3: Normalise to Float32 [0, 1]
  final floatData = Float32List(ts * ts * 3);
  int idx = 0;
  for (int r = 0; r < ts; r++) {
    for (int c = 0; c < ts; c++) {
      final pixel = canvas.getPixel(c, r);
      floatData[idx++] = pixel.r / 255.0;
      floatData[idx++] = pixel.g / 255.0;
      floatData[idx++] = pixel.b / 255.0;
    }
  }

  return _PreprocessResult(
    floatData: floatData,
    padLeft: padLeft,
    padTop: padTop,
    scale: scale,
  );
}

// ─── Public API ───────────────────────────────────────────────────────────────

/// Pure-Dart preprocessing fallback.
///
/// Converts [image] (YUV420) → letterboxed 640×640 Float32 tensor.
/// Runs in a worker isolate via [compute] — never blocks the UI thread.
///
/// Returns a [PreprocessResult] on success, or `null` if the isolate fails.
class DartPreprocessor {
  /// Preprocesses [image] using the pure-Dart pipeline.
  ///
  /// Equivalent to the native `preprocessFrame` call minus blur-check and CLAHE.
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
