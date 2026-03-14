import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

class ImageProcessor {
  static const int inputSize = 224;

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

    final cropped = img.copyCrop(fullImage, x: cx, y: cy, width: cw, height: ch);
    final resized = img.copyResize(cropped, width: inputSize, height: inputSize);
    return _normalizeImage(resized);
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
        final int uvIndex =
            (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

        final int yValue = yBytes[yIndex] & 0xFF;
        final int uValue = uBytes[uvIndex] & 0xFF;
        final int vValue = vBytes[uvIndex] & 0xFF;

        int r = (yValue + 1.402 * (vValue - 128)).round();
        int g =
            (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
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
    final Float32List result =
        Float32List(1 * inputSize * inputSize * 3);
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
