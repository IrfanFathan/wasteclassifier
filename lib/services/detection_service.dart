import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detection.dart';
import '../services/opencv_pipeline.dart';
import '../services/detection_smoother.dart';
import '../utils/detection_constants.dart';

/// Full-frame TFLite classification service for Teachable Machine models.
///
/// Teachable Machine exports a classification model (NOT object detection):
///   - Input:  [1, 224, 224, 3] NHWC, float32, normalised [0, 1].
///   - Output: [1, numClasses]   flat probability vector.
///
/// The service classifies the entire camera frame and returns a single
/// [Detection] with a full-frame bounding box and the top predicted class.
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

    // Log model tensor shapes for debugging.
    final inputTensor = _interpreter!.getInputTensor(0);
    final outputTensor = _interpreter!.getOutputTensor(0);
    debugPrint(
      'DetectionService: model loaded, ${_labels.length} labels'
      '\n  input:  ${inputTensor.shape} ${inputTensor.type}'
      '\n  output: ${outputTensor.shape} ${outputTensor.type}',
    );
  }

  /// Processes a single camera frame through the classification pipeline:
  ///   Preprocessing -> TFLite inference -> top-class selection -> smoothing.
  ///
  /// Returns `null` if the frame was skipped (throttled, blurry, or not ready).
  /// Returns a list with a single [Detection] (full-frame box) on success,
  /// or an empty list if the top class is below the confidence threshold.
  Future<List<Detection>?> processFrame(CameraImage image) async {
    if (!isReady) return null;
    if (!_shouldRunInference()) return null;

    // Step 1: Preprocess (resize to 224×224, normalise)
    final preprocessed = await OpenCVPipeline.preprocessFrame(image);
    if (preprocessed == null) return null;

    // Step 2: Run TFLite classification
    final result = _runClassification(preprocessed.floatData);
    if (result == null) return null;

    // Step 3: Build detection with full-frame bounding box
    final (label, confidence) = result;

    if (confidence < kConfidenceThreshold) {
      return _smoother.smooth([]);
    }

    final detection = Detection(
      box: Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      label: label,
      confidence: confidence,
    );

    // Step 4: Temporal smoothing
    return _smoother.smooth([detection]);
  }

  /// Runs TFLite classification on preprocessed float data.
  ///
  /// Returns `(label, confidence)` for the top predicted class, or null on error.
  (String, double)? _runClassification(List<double> floatData) {
    if (_interpreter == null) return null;

    try {
      final outputTensor = _interpreter!.getOutputTensor(0);
      final outputShape = outputTensor.shape;

      // Teachable Machine output: [1, numClasses]
      final numClasses = outputShape.last;

      // Prepare input as Float32List
      final input = Float32List.fromList(floatData);

      // Allocate output buffer: [1][numClasses]
      final output = [List<double>.filled(numClasses, 0.0)];

      _interpreter!.run([input], output);

      // Find the class with the highest probability
      int bestIdx = 0;
      double bestScore = 0.0;
      for (int i = 0; i < numClasses; i++) {
        final score = output[0][i];
        if (score > bestScore) {
          bestScore = score;
          bestIdx = i;
        }
      }

      final label = bestIdx < _labels.length
          ? _labels[bestIdx]
          : 'Unknown_$bestIdx';

      return (label, bestScore);
    } catch (e) {
      debugPrint('DetectionService classification error: $e');
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
