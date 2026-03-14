import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

// ─── Zone Result ──────────────────────────────────────────────────────────

/// A preprocessed image zone ready for TFLite inference.
///
/// [tensor] is a normalized Float32 tensor of shape [1, inputSize, inputSize, 3].
/// [cx] / [cy] are the pixel coordinates of the zone's centre in the original
/// camera frame — use these as the detected-object position.
class ZoneResult {
  final Float32List tensor;
  final int cx;
  final int cy;

  const ZoneResult({required this.tensor, required this.cx, required this.cy});
}

// ─── ImageProcessor ───────────────────────────────────────────────────────

class ImageProcessor {
  static const int inputSize = 224;

  // ─── Native OpenCV channel ─────────────────────────────────────────────
  static const MethodChannel _channel = MethodChannel('opencv_pipeline');

  /// Cached availability flag.
  /// null  = not yet checked
  /// true  = native library loaded on the Android side
  /// false = unavailable; use Dart fallback
  static bool? _nativeReady;

  /// Queries the native side once and caches the result.
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

  /// Scans the three horizontal zones of [image] using the OpenCV JNI
  /// pipeline when available, or falls back to pure Dart otherwise.
  ///
  /// The batch native call transfers the YUV planes only once regardless of
  /// the number of zones, which is significantly faster than three separate
  /// [scanHorizontalZones] calls.
  static Future<List<ZoneResult>> scanHorizontalZonesAsync(
    CameraImage image,
  ) async {
    final native = await isNativeAvailable();
    if (!native) return scanHorizontalZones(image);

    try {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final raw = await _channel
          .invokeMethod<Float32List>('preprocess_horizontal_zones', {
            'y_plane': yPlane.bytes,
            'u_plane': uPlane.bytes,
            'v_plane': vPlane.bytes,
            'y_row_stride': yPlane.bytesPerRow,
            'uv_row_stride': uPlane.bytesPerRow,
            'uv_pixel_stride': uPlane.bytesPerPixel ?? 1,
            'width': image.width,
            'height': image.height,
            'target_size': inputSize,
          });

      if (raw == null) {
        _nativeReady = false;
        return scanHorizontalZones(image);
      }

      // The native function returns 3 zones concatenated.
      // Recompute zone centres (identical to the Dart path).
      final fw = image.width;
      final fh = image.height;
      final zoneW = fw ~/ 3;
      final cy = fh ~/ 2;
      final zoneLen = inputSize * inputSize * 3;

      return [
        ZoneResult(
          tensor: Float32List.sublistView(raw, 0, zoneLen),
          cx: zoneW ~/ 2,
          cy: cy,
        ),
        ZoneResult(
          tensor: Float32List.sublistView(raw, zoneLen, zoneLen * 2),
          cx: zoneW + zoneW ~/ 2,
          cy: cy,
        ),
        ZoneResult(
          tensor: Float32List.sublistView(raw, zoneLen * 2, zoneLen * 3),
          cx: zoneW * 2 + (fw - zoneW * 2) ~/ 2,
          cy: cy,
        ),
      ];
    } catch (e) {
      debugPrint('OpenCV native zone scan failed: $e');
      _nativeReady = false; // disable for subsequent frames
      return scanHorizontalZones(image);
    }
  }

  /// Converts a YUV420 CameraImage to an RGB [img.Image].
  ///
  /// This is the shared first step for both detection and classification.
  static img.Image convertToRgb(CameraImage cameraImage) {
    return _convertYUV420toRGB(cameraImage);
  }

  /// Converts a YUV420 CameraImage to a normalized Float32 tensor
  /// suitable for a TFLite model with input shape [1, 224, 224, 3].
  ///
  /// This processes the **entire** frame as a single input.
  static Float32List processImage(CameraImage cameraImage) {
    final convertedImage = _convertYUV420toRGB(cameraImage);
    final resized = img.copyResize(
      convertedImage,
      width: inputSize,
      height: inputSize,
    );
    return _normalizeImage(resized);
  }

  /// Crops the region at ([x], [y]) with size ([w] × [h]) from [fullImage],
  /// resizes to 224×224, and normalises for TFLite inference.
  ///
  /// Use this to classify a specific detected object region.
  static Float32List processRegion(
    img.Image fullImage,
    int x,
    int y,
    int w,
    int h,
  ) {
    // Clamp bounds to stay within the image.
    final cx = x.clamp(0, fullImage.width - 1);
    final cy = y.clamp(0, fullImage.height - 1);
    final cw = w.clamp(1, fullImage.width - cx);
    final ch = h.clamp(1, fullImage.height - cy);

    final cropped = img.copyCrop(
      fullImage,
      x: cx,
      y: cy,
      width: cw,
      height: ch,
    );
    final resized = img.copyResize(
      cropped,
      width: inputSize,
      height: inputSize,
    );
    return _normalizeImage(resized);
  }

  /// Divides the camera frame into three equal horizontal zones
  /// (left / centre / right) and returns one [ZoneResult] per zone.
  ///
  /// The YUV→RGB conversion is performed **once** for the full frame;
  /// the three regions are then cropped from that single decoded image,
  /// which is significantly cheaper than decoding three times.
  ///
  /// Each zone's [ZoneResult.cx] reflects the actual horizontal pixel
  /// centre of that zone in the original frame, so the caller can map
  /// it directly to the 8×8 grid without any additional offset logic.
  static List<ZoneResult> scanHorizontalZones(CameraImage image) {
    // Single YUV → RGB decode for the full frame.
    final rgb = _convertYUV420toRGB(image);
    final fw = image.width;
    final fh = image.height;
    final zoneW = fw ~/ 3;
    final cy = fh ~/ 2; // zones span the full height; vertical centre is mid

    return [
      // Left zone: columns 0 … zoneW-1
      ZoneResult(
        tensor: processRegion(rgb, 0, 0, zoneW, fh),
        cx: zoneW ~/ 2,
        cy: cy,
      ),
      // Centre zone: columns zoneW … 2*zoneW-1
      ZoneResult(
        tensor: processRegion(rgb, zoneW, 0, zoneW, fh),
        cx: zoneW + zoneW ~/ 2,
        cy: cy,
      ),
      // Right zone: columns 2*zoneW … fw-1 (absorbs rounding remainder)
      ZoneResult(
        tensor: processRegion(rgb, zoneW * 2, 0, fw - zoneW * 2, fh),
        cx: zoneW * 2 + (fw - zoneW * 2) ~/ 2,
        cy: cy,
      ),
    ];
  }

  static img.Image _convertYUV420toRGB(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final img.Image output = img.Image(width: width, height: height);

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;

    final int yRowStride = yPlane.bytesPerRow;
    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yIndex = y * yRowStride + x;
        final int uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

        final int yValue = yBytes[yIndex] & 0xFF;
        final int uValue = uBytes[uvIndex] & 0xFF;
        final int vValue = vBytes[uvIndex] & 0xFF;

        int r = (yValue + 1.402 * (vValue - 128)).round();
        int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
            .round();
        int b = (yValue + 1.772 * (uValue - 128)).round();

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        output.setPixelRgb(x, y, r, g, b);
      }
    }

    return output;
  }

  static Float32List _normalizeImage(img.Image image) {
    final Float32List result = Float32List(1 * inputSize * inputSize * 3);
    int index = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = image.getPixel(x, y);
        result[index++] = pixel.r / 255.0;
        result[index++] = pixel.g / 255.0;
        result[index++] = pixel.b / 255.0;
      }
    }
    return result;
  }
}
