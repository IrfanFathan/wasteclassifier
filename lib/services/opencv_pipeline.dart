import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../models/detection.dart';
import '../utils/detection_constants.dart';

// ─── Isolate message type ──────────────────────────────────────────────────

typedef _FallbackMsg = ({
  Uint8List yBytes,
  Uint8List uBytes,
  Uint8List vBytes,
  int yRowStride,
  int uvRowStride,
  int uvPixelStride,
  int width,
  int height,
  int targetSize,
});

/// Top-level function for [compute] — performs pure-Dart YUV→RGB conversion,
/// letterbox resize, and float32 normalization in a worker isolate.
///
/// Returns `(floatData, padLeft, padTop, scale)` or `null` if decoding fails.
(Float32List, int, int, double)? _dartFallbackInIsolate(_FallbackMsg msg) {
  final srcW = msg.width;
  final srcH = msg.height;
  final targetSize = msg.targetSize;

  // ── 1. YUV420 → RGB ──────────────────────────────────────────────────────
  final rgb = img.Image(width: srcW, height: srcH);
  for (int y = 0; y < srcH; y++) {
    for (int x = 0; x < srcW; x++) {
      final yIdx = y * msg.yRowStride + x;
      final uvIdx = (y ~/ 2) * msg.uvRowStride + (x ~/ 2) * msg.uvPixelStride;

      final yVal = msg.yBytes[yIdx] & 0xFF;
      final uVal = msg.uBytes[uvIdx] & 0xFF;
      final vVal = msg.vBytes[uvIdx] & 0xFF;

      final r = (yVal + 1.402 * (vVal - 128)).round().clamp(0, 255);
      final g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128))
          .round()
          .clamp(0, 255);
      final b = (yVal + 1.772 * (uVal - 128)).round().clamp(0, 255);

      rgb.setPixelRgb(x, y, r, g, b);
    }
  }

  // ── 2. Letterbox resize to targetSize × targetSize (gray pad = 114) ──────
  final scale = (targetSize / srcW).compareTo(targetSize / srcH) <= 0
      ? targetSize / srcW
      : targetSize / srcH;

  final scaledW = (srcW * scale).round();
  final scaledH = (srcH * scale).round();

  final padLeft = (targetSize - scaledW) ~/ 2;
  final padTop = (targetSize - scaledH) ~/ 2;

  final resized = img.copyResize(rgb, width: scaledW, height: scaledH);

  // Fill canvas with gray (114, 114, 114).
  final canvas = img.Image(width: targetSize, height: targetSize);
  img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
  img.compositeImage(canvas, resized, dstX: padLeft, dstY: padTop);

  // ── 3. Normalize [0, 1] ───────────────────────────────────────────────────
  final tensorLen = targetSize * targetSize * 3;
  final floatData = Float32List(tensorLen);
  int idx = 0;
  for (int row = 0; row < targetSize; row++) {
    for (int col = 0; col < targetSize; col++) {
      final pixel = canvas.getPixel(col, row);
      floatData[idx++] = pixel.r / 255.0;
      floatData[idx++] = pixel.g / 255.0;
      floatData[idx++] = pixel.b / 255.0;
    }
  }

  return (floatData, padLeft, padTop, scale);
}

// ─── OpenCVPipeline ───────────────────────────────────────────────────────

/// Dart-side bridge to the native OpenCV preprocessing pipeline.
///
/// Sends raw YUV camera frames over the `opencv_pipeline` MethodChannel
/// and receives back a preprocessed 640x640x3 float32 tensor plus
/// letterbox metadata for coordinate unmapping.
///
/// When the native OpenCV library is unavailable the pipeline falls back
/// to a pure-Dart implementation (YUV→RGB, letterbox, normalize) run in a
/// worker isolate via [compute] so the UI thread is never blocked.
/// The fallback omits the blur check and CLAHE enhancement.
class OpenCVPipeline {
  static const _channel = MethodChannel('opencv_pipeline');

  /// Cached availability flag (null = not yet checked).
  static bool? _nativeReady;

  /// Returns true if the native OpenCV library is loaded and functional.
  static Future<bool> isNativeAvailable() async {
    if (_nativeReady != null) return _nativeReady!;
    try {
      _nativeReady =
          await _channel.invokeMethod<bool>('is_opencv_available') ?? false;
    } catch (_) {
      _nativeReady = false;
    }
    return _nativeReady!;
  }

  /// Preprocesses a camera frame.
  ///
  /// **Native path** (OpenCV available):
  ///   blur check -> CLAHE -> letterbox resize to [kInputSize]×[kInputSize] -> normalise.
  ///
  /// **Dart fallback** (OpenCV unavailable):
  ///   YUV→RGB -> letterbox resize -> normalise (no blur check, no CLAHE).
  ///   Runs in a worker isolate to avoid blocking the UI thread.
  ///
  /// Returns a [PreprocessResult] on success, or `null` if:
  ///   - The frame is too blurry (native path only, below [kBlurSkipThreshold]).
  ///   - Both the native call and the Dart fallback fail.
  static Future<PreprocessResult?> preprocessFrame(CameraImage image) async {
    final native = await isNativeAvailable();

    if (native) {
      final result = await _tryNative(image);
      if (result != null) return result;
      // Native failed mid-stream; fall through to Dart fallback.
    }

    return _dartFallback(image);
  }

  // ── Native path ───────────────────────────────────────────────────────────

  static Future<PreprocessResult?> _tryNative(CameraImage image) async {
    try {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final raw = await _channel.invokeMethod<Float32List>('preprocess_frame', {
        'y_plane': yPlane.bytes,
        'u_plane': uPlane.bytes,
        'v_plane': vPlane.bytes,
        'y_row_stride': yPlane.bytesPerRow,
        'uv_row_stride': uPlane.bytesPerRow,
        'uv_pixel_stride': uPlane.bytesPerPixel ?? 1,
        'width': image.width,
        'height': image.height,
        'target_size': kInputSize,
        'blur_threshold': kBlurSkipThreshold,
      });

      if (raw == null) {
        _nativeReady = false;
        return null;
      }

      // The native side appends 4 metadata floats at the end of the array:
      //   [N+0] padLeft, [N+1] padTop, [N+2] scale, [N+3] skipped
      final tensorLen = kInputSize * kInputSize * 3;
      final skipped = raw[tensorLen + 3] == 1.0;
      if (skipped) return null; // frame was blurry — skip silently

      return PreprocessResult(
        floatData: raw.sublist(0, tensorLen),
        padLeft: raw[tensorLen + 0].round(),
        padTop: raw[tensorLen + 1].round(),
        scale: raw[tensorLen + 2].toDouble(),
      );
    } catch (e) {
      debugPrint('OpenCV preprocessFrame failed: $e');
      _nativeReady = false;
      return null;
    }
  }

  // ── Dart fallback ─────────────────────────────────────────────────────────

  static Future<PreprocessResult?> _dartFallback(CameraImage image) async {
    try {
      final msg = (
        yBytes: image.planes[0].bytes,
        uBytes: image.planes[1].bytes,
        vBytes: image.planes[2].bytes,
        yRowStride: image.planes[0].bytesPerRow,
        uvRowStride: image.planes[1].bytesPerRow,
        uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
        width: image.width,
        height: image.height,
        targetSize: kInputSize,
      );

      final result = await compute(_dartFallbackInIsolate, msg);
      if (result == null) return null;

      final (floatData, padLeft, padTop, scale) = result;
      return PreprocessResult(
        floatData: floatData,
        padLeft: padLeft,
        padTop: padTop,
        scale: scale,
      );
    } catch (e) {
      debugPrint('Dart fallback preprocessFrame failed: $e');
      return null;
    }
  }
}
