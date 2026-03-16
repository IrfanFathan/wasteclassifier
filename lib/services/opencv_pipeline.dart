import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/detection.dart';
import '../utils/detection_constants.dart';

/// Dart-side bridge to the native OpenCV preprocessing pipeline.
///
/// Sends raw YUV camera frames over the `opencv_pipeline` MethodChannel
/// and receives back a preprocessed 640x640x3 float32 tensor plus
/// letterbox metadata for coordinate unmapping.
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

  /// Preprocesses a camera frame using the native OpenCV pipeline:
  ///   blur check -> CLAHE -> letterbox resize to [kInputSize]x[kInputSize] -> normalise.
  ///
  /// Returns a [PreprocessResult] on success, or `null` if:
  ///   - The frame is too blurry (below [kBlurSkipThreshold]).
  ///   - The native library is unavailable.
  ///   - The native call fails.
  static Future<PreprocessResult?> preprocessFrame(CameraImage image) async {
    final native = await isNativeAvailable();
    if (!native) return null;

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
      if (skipped) return null;

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
}
