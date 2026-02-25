import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_cameraError != null) return _cameraErrorWidget();
    if (!_cameraReady || _cameraController == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF4CAF50)),
            SizedBox(height: 16),
            Text('Initializing camera...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    final size = MediaQuery.of(context).size;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Full-screen Camera Preview
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.width * _cameraController!.value.aspectRatio,
            child: CameraPreview(_cameraController!),
          ),
        ),

        // 2. Translucent 3x3 Grid
        Positioned.fill(
          child: CustomPaint(painter: _GridPainter()),
        ),

        // 3. Central Reticle
        Center(
          child: _buildReticle(),
        ),

        // 4. Floating Top Bar
        Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          left: 16,
          right: 16,
          child: _buildTopBar(),
        ),

        // 5. Result Floating Card
        Positioned(
          bottom: 150,
          left: 20,
          right: 20,
          child: _buildFloatingResultCard(),
        ),

        // 6. Bottom Control Deck (Gradient + Shutter)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildBottomControlDeck(),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: _openSettings,
          icon: const Icon(Icons.tune, color: Colors.white, size: 28),
          style: IconButton.styleFrom(backgroundColor: Colors.black45),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('Waste Classifier', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        IconButton(
          onPressed: _confirmChangeModel,
          icon: const Icon(Icons.swap_horiz, color: Colors.white, size: 28),
          style: IconButton.styleFrom(backgroundColor: Colors.black45),
        ),
      ],
    );
  }

  Widget _buildReticle() {
    final activeColor = _state == DetectionState.detected && _detectedBin != null 
        ? Color(_detectedBin!.colorHex) 
        : (_state == DetectionState.unmapped ? const Color(0xFFFF9800) : Colors.white54);
        
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _state != DetectionState.waiting ? 180 : 150,
      height: _state != DetectionState.waiting ? 180 : 150,
      child: Stack(
        children: [
          Positioned(top: 0, left: 0, child: _corner(activeColor, top: true, left: true)),
          Positioned(top: 0, right: 0, child: _corner(activeColor, top: true, left: false)),
          Positioned(bottom: 0, left: 0, child: _corner(activeColor, top: false, left: true)),
          Positioned(bottom: 0, right: 0, child: _corner(activeColor, top: false, left: false)),
          Center(
             child: Icon(Icons.add, color: activeColor.withValues(alpha: 0.5), size: 28),
          ),
        ],
      ),
    );
  }

  Widget _corner(Color color, {required bool top, required bool left}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        border: Border(
           top: top ? BorderSide(color: color, width: 3) : BorderSide.none,
           bottom: !top ? BorderSide(color: color, width: 3) : BorderSide.none,
           left: left ? BorderSide(color: color, width: 3) : BorderSide.none,
           right: !left ? BorderSide(color: color, width: 3) : BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildFloatingResultCard() {
    if (_state == DetectionState.waiting) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF16213E).withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
             Text('Point camera at an object', style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
             if (!_modelReady)
               Padding(
                 padding: const EdgeInsets.only(top: 4),
                 child: Text('Loading model...', style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
               ),
          ],
        ),
      );
    }
    
    if (_state == DetectionState.unmapped) {
       return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF16213E).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFFF9800), width: 1.5),
        ),
        child: Column(
          children: [
             const Text('⚠️', style: TextStyle(fontSize: 24)),
             const SizedBox(height: 8),
             Text(_detectedLabel, style: GoogleFonts.outfit(color: const Color(0xFFFF9800), fontWeight: FontWeight.bold, fontSize: 18), textAlign: TextAlign.center),
             const SizedBox(height: 4),
             Text('Not mapped to any bin', style: GoogleFonts.inter(color: Colors.white70)),
          ],
        ),
       );
    }

    final bin = _detectedBin!;
    final binColor = Color(bin.colorHex);
    return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF16213E).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: binColor, width: 2),
        ),
        child: Column(
          children: [
             Text(_detectedLabel, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
             const SizedBox(height: 4),
             Text('${(_confidence * 100).toStringAsFixed(1)}% Match', style: GoogleFonts.inter(color: Colors.white54, fontSize: 13)),
             const SizedBox(height: 12),
             Container(
               padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
               decoration: BoxDecoration(
                 color: binColor,
                 borderRadius: BorderRadius.circular(20),
               ),
               child: Row(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   Text(bin.emoji, style: const TextStyle(fontSize: 20)),
                   const SizedBox(width: 8),
                   Text(bin.name, style: GoogleFonts.outfit(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
                 ],
               ),
             ),
          ],
        ),
    );
  }

  Widget _buildBottomControlDeck() {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.8),
            Colors.transparent,
          ],
        ),
      ),
      child: Center(
         child: GestureDetector(
            onTap: () {
              // Dummy shutter action
            },
            child: Container(
               width: 72,
               height: 72,
               decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white38, width: 4),
               ),
               child: Center(
                  child: Container(
                     width: 56,
                     height: 56,
                     decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black26, width: 1.5),
                     ),
                  ),
               ),
            ),
         ),
      ),
    );
  }

  Widget _cameraErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(_cameraError!, style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 15), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 1.0;

    canvas.drawLine(Offset(size.width / 3, 0), Offset(size.width / 3, size.height), paint);
    canvas.drawLine(Offset(size.width * 2 / 3, 0), Offset(size.width * 2 / 3, size.height), paint);
    canvas.drawLine(Offset(0, size.height / 3), Offset(size.width, size.height / 3), paint);
    canvas.drawLine(Offset(0, size.height * 2 / 3), Offset(size.width, size.height * 2 / 3), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
