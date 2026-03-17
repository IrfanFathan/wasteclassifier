import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/detection.dart';
import '../services/dart_preprocessor.dart';
import '../utils/detection_constants.dart';

/// Dart-side bridge to the native OpenCV preprocessing pipeline.
///
/// Sends raw YUV camera frames over the `opencv_pipeline` MethodChannel
/// and receives back a preprocessed 640×640×3 float32 tensor plus
/// letterbox metadata for coordinate unmapping.
///
/// When the native OpenCV library is unavailable (e.g. OpenCV SDK not
/// configured), the call transparently falls back to [DartPreprocessor],
/// which performs the same letterbox pipeline in a Dart isolate — without
/// blur-check or CLAHE, but fully functional for inference.
class OpenCVPipeline {
  static const _channel = MethodChannel('opencv_pipeline');

  /// Cached availability flag (null = not yet checked).
  ///
  /// Set exactly once from [isNativeAvailable] — reflects whether the
  /// native library was compiled with OpenCV support at build time.
  ///
  /// Intentionally NOT reset on per-frame errors: a single JNI hiccup
  /// should not permanently disable native preprocessing for the session.
  static bool? _nativeReady;

  /// Returns true if the native OpenCV library is loaded and functional.
  ///
  /// Cached after the first call so subsequent queries are instant.
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

  /// Preprocesses a camera frame through the full pipeline.
  ///
  /// **Native path** (OpenCV compiled in):
  ///   blur check → CLAHE → letterbox resize to [kInputSize]×[kInputSize] → normalise.
  ///   Returns `null` for blurry frames below [kBlurSkipThreshold].
  ///
  /// **Dart fallback** (OpenCV unavailable OR native call fails this frame):
  ///   YUV→RGB → letterbox resize → normalise.
  ///   No blur-check or CLAHE. Runs in a worker isolate via [compute].
  ///
  /// Returns `null` only if both paths fail or the frame was flagged blurry
  /// by the native path.
  static Future<PreprocessResult?> preprocessFrame(CameraImage image) async {
    final native = await isNativeAvailable();

    if (native) {
      final result = await _tryNative(image);
      // result == null can mean:
      //   (a) blurry frame — skip it (don't fall back, return null)
      //   (b) transient JNI error — fall through to Dart fallback
      // We distinguish the two via the _blurryFrame sentinel set in _tryNative.
      if (result != null) return result;
      if (_lastFrameWasBlurry) {
        _lastFrameWasBlurry = false;
        return null; // truly blurry — skip without fallback
      }
      debugPrint(
        '[OpenCVPipeline] Native call failed this frame — using Dart fallback',
      );
    }

    return DartPreprocessor.preprocessFrame(image);
  }

  // Sentinel set by _tryNative when the native side signals a blurry frame.
  static bool _lastFrameWasBlurry = false;

  // ── Native path ─────────────────────────────────────────────────────────

  /// Attempts the native `preprocess_frame` call.
  ///
  /// Returns `null` on any failure **without** modifying [_nativeReady] —
  /// a per-frame failure does not disable the native path for future frames.
  static Future<PreprocessResult?> _tryNative(CameraImage image) async {
    _lastFrameWasBlurry = false;
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

      if (raw == null) return null; // native returned null — treat as transient

      // The native side appends 4 metadata floats at the end of the array:
      //   [N+0] padLeft, [N+1] padTop, [N+2] scale, [N+3] skipped (1.0 = blurry)
      final tensorLen = kInputSize * kInputSize * 3;
      if (raw[tensorLen + 3] == 1.0) {
        _lastFrameWasBlurry = true;
        return null; // blurry frame — caller will skip
      }

      return PreprocessResult(
        floatData: raw.sublist(0, tensorLen),
        padLeft: raw[tensorLen + 0].round(),
        padTop: raw[tensorLen + 1].round(),
        scale: raw[tensorLen + 2].toDouble(),
      );
    } catch (e) {
      // Transient failure (OOM, timeout, etc.) — log but do NOT set
      // _nativeReady = false.  The native path stays enabled for the next frame.
      debugPrint('[OpenCVPipeline] _tryNative error (transient): $e');
      return null;
    }
  }
}
