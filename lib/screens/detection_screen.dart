import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/app_config.dart';
import '../models/bin_category.dart';
import '../utils/config_manager.dart';
import '../utils/image_processor.dart';
import '../utils/model_manager.dart';
import 'bin_setup_screen.dart';
import 'upload_screen.dart';

/// Represents the current detection state.
enum DetectionState { waiting, detected, unmapped }

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  // ─── Camera ───
  CameraController? _cameraController;
  bool _cameraReady = false;
  String? _cameraError;

  // ─── Model ───
  Interpreter? _interpreter;
  bool _modelReady = false;
  bool _isProcessing = false;

  // ─── Config ───
  AppConfig? _config;
  List<String> _labels = [];

  // ─── Detection Result ───
  DetectionState _state = DetectionState.waiting;
  String _detectedLabel = '';
  double _confidence = 0.0;
  BinCategory? _detectedBin;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadConfig();
    await _loadModel();
    await _initCamera();
  }

  Future<void> _loadConfig() async {
    final config = await ConfigManager.loadConfig();
    final labels = await ConfigManager.loadLabels();
    if (mounted) {
      setState(() {
        _config = config;
        _labels = labels;
      });
    }
  }

  Future<void> _loadModel() async {
    try {
      final modelPath = await ModelManager.getModelPath();
      final interpreter = Interpreter.fromFile(
        File(modelPath),
        options: InterpreterOptions()..threads = 2,
      );
      if (mounted) {
        setState(() {
          _interpreter = interpreter;
          _modelReady = true;
        });
      }
    } catch (e) {
      debugPrint('Model load error: $e');
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _cameraError = 'No cameras available on this device.');
        }
        return;
      }

      // Prefer back camera
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.medium,
        imageFormatGroup: ImageFormatGroup.yuv420,
        enableAudio: false,
      );

      await controller.initialize();
      if (!mounted) return;

      setState(() {
        _cameraController = controller;
        _cameraReady = true;
      });

      controller.startImageStream(_onCameraFrame);
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _cameraError = e.code == 'CameraAccessDenied'
              ? 'Camera permission denied. Please enable it in App Settings.'
              : 'Camera error: ${e.description}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cameraError = 'Camera init failed: $e');
      }
    }
  }

  void _onCameraFrame(CameraImage image) {
    if (_isProcessing || !_modelReady || _interpreter == null || _config == null) {
      return;
    }
    _isProcessing = true;
    _runInference(image);
  }

  void _runInference(CameraImage image) {
    try {
      // ImageProcessor returns a flat Float32List of length 1*224*224*3 = 150528
      final inputFlat = ImageProcessor.processImage(image);

      // tflite_flutter 0.12.x: for input, pass as Uint8List (raw bytes).
      // getInputShapeIfDifferent returns null for Uint8List, so no resize is
      // attempted. setTo() copies the raw bytes directly into the native tensor.
      // This avoids a shape mismatch (Float32List.shape=[150528] vs model [1,224,224,3]).
      final inputBytes = inputFlat.buffer.asUint8List();

      // Output: model produces shape [1, numClasses].
      // Pass List<List<double>> so _duplicateList shape check passes.
      final numClasses = _labels.length;
      final outputBuffer = List<double>.filled(numClasses, 0.0);
      final output = [outputBuffer]; // shape [1, numClasses]

      _interpreter!.run(inputBytes, output);

      final probabilities = output[0];
      double maxProb = 0.0;
      int maxIdx = 0;
      for (int i = 0; i < probabilities.length; i++) {
        if (probabilities[i] > maxProb) {
          maxProb = probabilities[i];
          maxIdx = i;
        }
      }

      final detectedLabel =
          maxIdx < _labels.length ? _labels[maxIdx] : 'Unknown';

      _processResult(detectedLabel, maxProb);
    } catch (e) {
      debugPrint('Inference error (skipping frame): $e');
    } finally {
      _isProcessing = false;
    }
  }

  void _processResult(String label, double confidence) {
    if (!mounted) return;
    final config = _config!;

    // Below threshold → waiting state
    if (confidence < config.confidenceThreshold) {
      if (_state != DetectionState.waiting) {
        setState(() => _state = DetectionState.waiting);
      }
      return;
    }

    // Check if label is a "nothing" label
    final isNothing = config.nothingLabels
        .any((n) => n.toLowerCase() == label.toLowerCase());
    if (isNothing) {
      if (_state != DetectionState.waiting) {
        setState(() => _state = DetectionState.waiting);
      }
      return;
    }

    // Find matching bin
    BinCategory? matchedBin;
    for (final bin in config.bins) {
      if (bin.mappedLabels.any((m) => m.toLowerCase() == label.toLowerCase())) {
        matchedBin = bin;
        break;
      }
    }

    setState(() {
      _detectedLabel = label;
      _confidence = confidence;
      if (matchedBin != null) {
        _state = DetectionState.detected;
        _detectedBin = matchedBin;
      } else {
        _state = DetectionState.unmapped;
        _detectedBin = null;
      }
    });
  }

  Future<void> _confirmChangeModel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Change Model',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will clear your model and all bin settings. Continue?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear & Change',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ModelManager.deleteModelFiles();
      await ConfigManager.clearAll();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const UploadScreen()),
        (_) => false,
      );
    }
  }

  Future<void> _openSettings() async {
    await _cameraController?.stopImageStream();
    final labels = await ConfigManager.loadLabels();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BinSetupScreen(
          labels: labels,
          existingConfig: _config,
        ),
      ),
    );
    await _loadConfig();
    _cameraController?.startImageStream(_onCameraFrame);
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        automaticallyImplyLeading: false,
        title: const Text(
          '♻️ Waste Classifier',
          style:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            tooltip: 'Bin Settings',
            onPressed: _openSettings,
          ),
          IconButton(
            icon:
                const Icon(Icons.swap_horiz_outlined, color: Colors.white),
            tooltip: 'Change Model',
            onPressed: _confirmChangeModel,
          ),
        ],
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_cameraError != null) {
      return _cameraErrorWidget();
    }
    if (!_cameraReady) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.greenAccent),
            SizedBox(height: 16),
            Text('Initializing camera...',
                style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    final binColor = _detectedBin != null
        ? Color(_detectedBin!.colorHex)
        : Colors.transparent;

    return Column(
      children: [
        // ─── Camera Preview (top 60%) ───
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Stack(
              children: [
                // Camera box with colored border glow
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: _state == DetectionState.detected
                        ? [
                            BoxShadow(
                              color: binColor.withValues(alpha: 0.6),
                              blurRadius: 18,
                              spreadRadius: 2,
                            )
                          ]
                        : [],
                    border: Border.all(
                      color: _state == DetectionState.detected
                          ? binColor
                          : _state == DetectionState.unmapped
                              ? const Color(0xFFFF9800)
                              : Colors.white12,
                      width: _state != DetectionState.waiting ? 2.5 : 1.0,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _cameraController != null
                        ? CameraPreview(_cameraController!)
                        : Container(color: const Color(0xFF0D0D1A)),
                  ),
                ),

                // Confidence bar at bottom of camera
                if (_state == DetectionState.detected)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(20)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 5,
                        width: double.infinity,
                        child: LinearProgressIndicator(
                          value: _confidence,
                          backgroundColor: Colors.transparent,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(binColor),
                          minHeight: 5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ─── Detection Result Panel (bottom 40%) ───
        Expanded(
          flex: 4,
          child: Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: _buildResultPanel(),
          ),
        ),
      ],
    );
  }

  Widget _buildResultPanel() {
    switch (_state) {
      case DetectionState.waiting:
        return _waitingState();
      case DetectionState.detected:
        return _detectedState();
      case DetectionState.unmapped:
        return _unmappedState();
    }
  }

  Widget _waitingState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.search,
            size: 52,
            color: Colors.white.withValues(alpha: 0.25)),
        const SizedBox(height: 16),
        Text(
          'Hold a waste item in front of the camera...',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 15,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        if (!_modelReady) ...[
          const SizedBox(height: 12),
          Text(
            'Loading model...',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _detectedState() {
    final bin = _detectedBin!;
    final binColor = Color(bin.colorHex);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          _detectedLabel,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '${(_confidence * 100).toStringAsFixed(1)}%',
          style: const TextStyle(
              color: Colors.grey,
              fontSize: 14,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 16),
        // Bin badge
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: binColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: binColor, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(bin.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text(
                bin.name,
                style: TextStyle(
                  color: binColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _unmappedState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _detectedLabel,
                style: const TextStyle(
                  color: Color(0xFFFF9800),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Not assigned to any bin',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          'This item is not assigned to any bin.\nGo to Settings to map it.',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
              height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _openSettings,
          icon: const Icon(Icons.settings_outlined, size: 16),
          label: const Text('Assign Now'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF9800),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _cameraErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off,
                size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              _cameraError!,
              style:
                  const TextStyle(color: Colors.redAccent, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
