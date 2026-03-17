import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detection.dart';
import '../services/opencv_pipeline.dart';
import '../services/nms_processor.dart';
import '../services/detection_smoother.dart';
import '../utils/detection_constants.dart';

/// Full-frame TFLite inference service.
///
/// Replaces the old grid-zone scanning pipeline with a single full-frame
/// inference call on a letterboxed 640x640 image.
///
/// Call [initialize] once with model path and labels, then [processFrame]
/// for each camera frame. Dispose with [dispose].
class DetectionService {
  Interpreter? _interpreter;
  List<String> _labels = [];
  final DetectionSmoother _smoother = DetectionSmoother();

  bool get isReady => _interpreter != null && _labels.isNotEmpty;

  // ─── Frame throttle ────────────────────────────────────────────────────
  DateTime _lastInference = DateTime.fromMillisecondsSinceEpoch(0);

  bool _shouldRunInference() {
    final now = DateTime.now();
    if (now.difference(_lastInference).inMilliseconds < kMaxFpsMs) return false;
    _lastInference = now;
    return true;
  }

  /// Loads the TFLite model and labels.
  Future<void> initialize({
    required String modelPath,
    required List<String> labels,
  }) async {
    _labels = labels;
    _interpreter = Interpreter.fromFile(
      File(modelPath),
      options: InterpreterOptions()..threads = 2,
    );
    debugPrint('DetectionService: model loaded, ${_labels.length} labels');
  }

  /// Processes a single camera frame through the full pipeline:
  ///   OpenCV preprocessing -> TFLite inference -> NMS -> temporal smoothing.
  ///
  /// Returns `null` if the frame was skipped (throttled, blurry, or not ready).
  Future<List<Detection>?> processFrame(CameraImage image) async {
    if (!isReady) return null;
    if (!_shouldRunInference()) return null;

    // Step 1: Preprocess via native OpenCV
    final preprocessed = await OpenCVPipeline.preprocessFrame(image);
    if (preprocessed == null) return null;

    // Step 2: Run TFLite inference
    final rawOutput = _runInference(preprocessed.floatData);
    if (rawOutput == null) return null;

    // Step 3: Post-process with NMS
    final detections = NmsProcessor.process(
      rawOutput: rawOutput,
      labels: _labels,
      padLeft: preprocessed.padLeft,
      padTop: preprocessed.padTop,
      scale: preprocessed.scale,
      origWidth: image.width,
      origHeight: image.height,
    );

    // Step 4: Temporal smoothing
    return _smoother.smooth(detections);
  }

  /// Runs TFLite inference on preprocessed float data.
  ///
  /// Returns the raw output reshaped to [numPredictions][numClasses + 4],
  /// or null on error.
  List<List<double>>? _runInference(List<double> floatData) {
    if (_interpreter == null) return null;

    try {
      final outputTensor = _interpreter!.getOutputTensor(0);

      final outputShape = outputTensor.shape; // [1, N, C] or [1, C, N]

      // Prepare input as Float32List
      final input = Float32List.fromList(floatData);

      // Determine output dimensions
      // YOLO11n outputs [1, 4+numClasses, 8400] (transposed) or [1, 8400, 4+numClasses]
      final dim1 = outputShape[1];
      final dim2 = outputShape[2];
      final numClasses = _labels.length;

      // Detect if output is transposed: if dim1 == 4+numClasses and dim2 >> dim1,
      // then the output is [1, features, predictions] and needs transposing.
      final bool isTransposed = dim1 == (4 + numClasses) && dim2 > dim1;

      final int numPredictions;
      final int numFeatures;
      if (isTransposed) {
        numFeatures = dim1;
        numPredictions = dim2;
      } else {
        numPredictions = dim1;
        numFeatures = dim2;
      }

      // Allocate output buffer
      final outputBuffer = List.generate(
        outputShape[1],
        (_) => List<double>.filled(outputShape[2], 0.0),
      );
      final output = [outputBuffer];

      _interpreter!.run([input], output);

      // Reshape to [numPredictions][numFeatures]
      final result = List.generate(numPredictions, (i) {
        if (isTransposed) {
          // output[0] is [features][predictions], we want [predictions][features]
          return List.generate(numFeatures, (f) => output[0][f][i]);
        } else {
          return output[0][i];
        }
      });

      return result;
    } catch (e) {
      debugPrint('DetectionService inference error: $e');
      return null;
    }
  }

  void resetSmoother() {
    _smoother.reset();
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
