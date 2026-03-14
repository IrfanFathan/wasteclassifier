import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/grid_mapper.dart';
import '../communication/robot_controller.dart';
import '../models/app_config.dart';
import '../models/bin_category.dart';
import '../models/calibration_config.dart';
import '../ui/grid_overlay_painter.dart';
import '../utils/config_manager.dart';
import '../utils/image_processor.dart';
import '../utils/model_manager.dart';
import '../utils/waste_locator.dart';
import '../services/esp32_service.dart';
import 'bin_setup_screen.dart';
import 'upload_screen.dart';

// ─── Detection State ──────────────────────────────────────────────────────

/// Represents the three possible detection outcomes.
enum DetectionState { waiting, detected, unmapped }

// ─── Grid Coordinate ──────────────────────────────────────────────────────
// Now uses GridPosition from lib/core/grid_mapper.dart
// (8×8 center-origin Cartesian system)

// ─── DetectionScreen ──────────────────────────────────────────────────────

/// Main camera screen for waste classification.
///
/// Features:
///   - Full-screen camera preview (correct 4:3 aspect ratio).
///   - 8×8 center-origin grid overlay with Cartesian labels.
///   - Active cell highlight showing where waste is located in frame.
///   - Bottom-anchored result panel showing (gridX, gridY) coordinates.
///   - Robot navigation command from [WasteLocator].
///   - Grid-based pick commands sent to ESP32 robotic arm controller.
class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen>
    with SingleTickerProviderStateMixin {
  // ─── Camera ─────────────────────────────────────────────────────────────
  CameraController? _cameraController;
  bool _cameraReady = false;
  String? _cameraError;

  // ─── Model ──────────────────────────────────────────────────────────────
  Interpreter? _interpreter;
  bool _modelReady = false;
  bool _isProcessing = false;

  // ─── Config ─────────────────────────────────────────────────────────────
  AppConfig? _config;
  List<String> _labels = [];
  CalibrationConfig _calibration = CalibrationConfig();

  // ─── Detection Result ───────────────────────────────────────────────────
  DetectionState _state = DetectionState.waiting;
  String _detectedLabel = '';
  double _confidence = 0.0;
  BinCategory? _detectedBin;

  // ─── Spatial / Grid ─────────────────────────────────────────────────────
  /// Active grid position where waste was detected (null when waiting).
  GridPosition? _activePosition;

  /// Robot navigation location from [WasteLocator].
  WasteLocation _wasteLocation = WasteLocation.unknown;

  // ─── ESP32 ──────────────────────────────────────────────────────────────
  DateTime? _lastEspTransmission;

  // ─── Frame throttle ──────────────────────────────────────────────────────
  /// Minimum interval between inference runs.  Skip frames that arrive faster.
  static const int _frameThrottleMs = 300;
  DateTime? _lastFrameProcessed;

  // ─── Animation ───────────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // ── Design tokens ────────────────────────────────────────────────────────
  static const Color _accentGreen = Color(0xFF00E676);
  static const Color _accentAmber = Color(0xFFFFD740);
  static const Color _accentRed = Color(0xFFFF5252);
  static const Color _accentCyan = Color(0xFF00B0FF);
  static const Color _panelBg = Color(0xE6121212); // 90% opaque dark

  @override
  void initState() {
    super.initState();

    // Lock the detection screen to landscape orientation.
    // Both left and right landscape are allowed so the user can hold the
    // device either way when mounted on a robot.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initialize();
  }

  // ─── Initialisation ──────────────────────────────────────────────────────

  Future<void> _initialize() async {
    await _loadConfig();
    await _loadModel();
    await _initCamera();
  }

  Future<void> _loadConfig() async {
    final config = await ConfigManager.loadConfig();
    final labels = await ConfigManager.loadLabels();
    final calibration = await ConfigManager.loadCalibration();
    if (mounted) {
      setState(() {
        _config = config;
        _labels = labels;
        if (calibration != null) _calibration = calibration;
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

  /// Starts the back camera at [ResolutionPreset.high] (native 4:3 on Android).
  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _cameraError = 'No cameras available on this device.');
        }
        return;
      }

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.high,
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
              ? 'Camera permission denied. Enable it in App Settings.'
              : 'Camera error: ${e.description}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cameraError = 'Camera init failed: $e');
      }
    }
  }

  // ─── Inference ───────────────────────────────────────────────────────────

  void _onCameraFrame(CameraImage image) {
    if (_isProcessing ||
        !_modelReady ||
        _interpreter == null ||
        _config == null) {
      return;
    }

    // Throttle: skip frames that arrive within the cooldown window.
    final now = DateTime.now();
    if (_lastFrameProcessed != null &&
        now.difference(_lastFrameProcessed!).inMilliseconds < _frameThrottleMs) {
      return;
    }
    _lastFrameProcessed = now;

    _isProcessing = true;
    _runInference(image);
  }

  Future<void> _runInference(CameraImage image) async {
    try {
      final numClasses = _labels.length;

      // ── Step 1: Scan 3 horizontal zones (left / centre / right) ───────
      // Uses OpenCV JNI native path when available (single plane-transfer),
      // falls back to pure Dart YUV→RGB + crop otherwise.
      final zones = await ImageProcessor.scanHorizontalZonesAsync(image);

      // ── Step 2: Run TFLite on each zone; keep the highest-confidence ──
      final outputBuffer = List<double>.filled(numClasses, 0.0);
      final output = [outputBuffer];

      double bestConf = 0.0;
      int bestLabelIdx = 0;
      int bestCx = image.width ~/ 2;
      int bestCy = image.height ~/ 2;

      for (final zone in zones) {
        // Reset output buffer between runs.
        for (int i = 0; i < numClasses; i++) {
          outputBuffer[i] = 0.0;
        }

        final inputBytes = zone.tensor.buffer.asUint8List();
        _interpreter!.run(inputBytes, output);

        int maxI = 0;
        double maxP = 0.0;
        for (int i = 0; i < numClasses; i++) {
          if (output[0][i] > maxP) {
            maxP = output[0][i];
            maxI = i;
          }
        }

        if (maxP > bestConf) {
          bestConf = maxP;
          bestLabelIdx = maxI;
          bestCx = zone.cx;
          bestCy = zone.cy;
        }
      }

      // ── Step 3: Process Results ────────────────────────────────────────
      final label =
          bestLabelIdx < _labels.length ? _labels[bestLabelIdx] : 'Unknown';
      _processResult(label, bestConf, bestCx, bestCy, image.width, image.height);
    } catch (e) {
      debugPrint('Inference error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Updates detection state from pixel coordinates.
  ///
  /// [cx], [cy]  — pixel centre of the detected object.
  /// [fw], [fh]  — frame dimensions.
  void _processResult(
    String label,
    double confidence,
    int cx,
    int cy,
    int fw,
    int fh,
  ) {
    if (!mounted) return;
    final config = _config!;

    // Below threshold → waiting.
    if (confidence < config.confidenceThreshold) {
      if (_state != DetectionState.waiting) {
        setState(() {
          _state = DetectionState.waiting;
          _activePosition = null;
          _wasteLocation = WasteLocation.unknown;
        });
      }
      return;
    }

    // Nothing label → waiting.
    final isNothing = config.nothingLabels.any(
      (n) => n.toLowerCase() == label.toLowerCase(),
    );
    if (isNothing) {
      if (_state != DetectionState.waiting) {
        setState(() {
          _state = DetectionState.waiting;
          _activePosition = null;
          _wasteLocation = WasteLocation.unknown;
        });
      }
      return;
    }

    // Find bin category.
    BinCategory? matchedBin;
    for (final bin in config.bins) {
      if (bin.mappedLabels.any((m) => m.toLowerCase() == label.toLowerCase())) {
        matchedBin = bin;
        break;
      }
    }

    // ── 8×8 Center-origin grid position ───────────────────────────────────
    final gridPos = GridMapper.fromPixel(
      pixelX: cx.toDouble(),
      pixelY: cy.toDouble(),
      frameWidth: fw,
      frameHeight: fh,
    );

    // ── Robot navigation (WasteLocator) ──────────────────────────────────
    final location = WasteLocator.compute(
      pixelX: cx,
      pixelY: cy,
      frameWidth: fw,
      frameHeight: fh,
      confidence: confidence,
      calibration: _calibration,
      minConfidence: config.confidenceThreshold,
    );

    setState(() {
      _detectedLabel = label;
      _confidence = confidence;
      _activePosition = gridPos;
      _wasteLocation = location;

      if (matchedBin != null) {
        _state = DetectionState.detected;
        _detectedBin = matchedBin;
        _transmitToEsp32(label, matchedBin, confidence, location, gridPos);
      } else {
        _state = DetectionState.unmapped;
        _detectedBin = null;
      }
    });
  }

  void _transmitToEsp32(
    String label,
    BinCategory bin,
    double confidence,
    WasteLocation location,
    GridPosition gridPos,
  ) {
    if (!Esp32Service().isConnected) return;

    // Throttle transmissions to once per second so we don't spam the ESP32
    final now = DateTime.now();
    if (_lastEspTransmission != null &&
        now.difference(_lastEspTransmission!).inMilliseconds < 1000) {
      return;
    }
    _lastEspTransmission = now;

    // Send waste classification data.
    Esp32Service().sendWasteData(
      label: label,
      binId: bin.id,
      binName: bin.name,
      confidence: confidence,
      direction: location.direction.name,
      distanceCm: location.estimatedDistanceCm,
      coordX: gridPos.centerX,
      coordY: gridPos.centerY,
      gridCell: gridPos.label,
      pixelX: gridPos.pixelX,
      pixelY: gridPos.pixelY,
    );

    // Also send the structured grid command for robotic arm.
    final command = RobotController.createRobotCommand(gridPos);
    Esp32Service().sendRobotCommand(command);
  }

  // ─── Settings ────────────────────────────────────────────────────────────

  Future<void> _confirmChangeModel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Change Model',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'This will clear your model and all bin settings. Continue?',
          style: GoogleFonts.inter(color: Colors.white60),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Clear & Change',
              style: GoogleFonts.inter(
                color: _accentRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ModelManager.deleteModelFiles();
      await ConfigManager.clearAll();
      if (!mounted) return;

      // Allow portrait mode for UploadScreen.
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

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

    // Switch to portrait mode explicitly for the BinSetupScreen.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BinSetupScreen(labels: labels, existingConfig: _config),
      ),
    );

    // Restore landscape mode when returning to the camera.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    await _loadConfig();
    _cameraController?.startImageStream(_onCameraFrame);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _interpreter?.close();
    // Restore all orientations when leaving the detection screen so that
    // other screens (upload, bin setup) are not locked to landscape.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.black, body: _buildBody());
  }

  Widget _buildBody() {
    if (_cameraError != null) return _buildErrorView();
    if (!_cameraReady || _cameraController == null) return _buildLoadingView();

    // Determine accent colour from current state.
    final accent = _stateAccent();

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── 1. Full-screen camera preview + grid (bounded to preview area) ──
        // Grid8x8Overlay is stacked INSIDE the AspectRatio so it is
        // constrained to the exact camera preview rectangle and never
        // bleeds into the black letterbox bars around it.
        Positioned.fill(
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: AspectRatio(
              // Use the camera's reported aspect ratio directly (width/height).
              // On Android this is ~0.75 in portrait, giving the correct 3:4
              // portrait representation of a 4:3 sensor.
              aspectRatio: _cameraController!.value.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(_cameraController!),
                  Grid8x8Overlay(
                    activePosition: _activePosition,
                    accentColor: accent,
                    pulseAnimation: _pulseAnim,
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── 2. Status badge (top-left) ──────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          child: _buildStatusBadge(accent),
        ),

        // ── 3. Action buttons (top-right) ───────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          right: MediaQuery.of(context).padding.right + 16,
          child: _buildActionButtons(),
        ),

        // ── 4. Bottom result panel ──────────────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildResultPanel(accent),
        ),
      ],
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Returns the accent colour for the current detection state.
  Color _stateAccent() {
    return switch (_state) {
      DetectionState.detected =>
        _detectedBin != null ? Color(_detectedBin!.colorHex) : _accentGreen,
      DetectionState.unmapped => _accentAmber,
      DetectionState.waiting => Colors.white38,
    };
  }

  // ─── Widget builders ──────────────────────────────────────────────────────

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: _accentGreen, strokeWidth: 2),
          const SizedBox(height: 20),
          Text(
            'Initialising camera…',
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_off_outlined,
              size: 56,
              color: _accentRed.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 16),
            Text(
              _cameraError!,
              style: GoogleFonts.inter(color: Colors.white60, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Top-left pill showing the scanning / detecting status.
  Widget _buildStatusBadge(Color accent) {
    final isDetected = _state != DetectionState.waiting;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDetected ? accent.withValues(alpha: 0.6) : Colors.white12,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ESP32 Connection indicator
          if (Esp32Service().isConnected) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _accentCyan,
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Dot indicator
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) => Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDetected
                    ? accent.withValues(alpha: _pulseAnim.value)
                    : Colors.white24,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isDetected ? 'DETECTED' : (_modelReady ? 'SCANNING' : 'LOADING'),
            style: GoogleFonts.inter(
              color: isDetected ? accent : Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  /// Top-right icon buttons for settings and model change.
  Widget _buildActionButtons() {
    return Row(
      children: [
        if (Esp32Service().isConnected) ...[
          _iconBtn(
            Icons.flash_on_rounded,
            () => Esp32Service().sendTrigger(),
            label: 'Trigger',
          ),
          const SizedBox(width: 8),
        ],
        _iconBtn(Icons.tune_rounded, _openSettings, label: 'Bin Setup'),
        const SizedBox(width: 8),
        _iconBtn(Icons.swap_horiz_rounded, _confirmChangeModel),
      ],
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, {String? label}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: label != null
            ? const EdgeInsets.symmetric(horizontal: 16)
            : const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _panelBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 20),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Bottom result panel — adapts to each detection state.
  Widget _buildResultPanel(Color accent) {
    return Container(
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
            color: _state != DetectionState.waiting
                ? accent.withValues(alpha: 0.5)
                : Colors.white10,
            width: 1,
          ),
        ),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: _state == DetectionState.waiting
          ? _buildWaitingContent()
          : _buildDetectionContent(accent),
    );
  }

  /// Panel content when no waste is detected yet.
  Widget _buildWaitingContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pull handle
        Container(
          width: 36,
          height: 3,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Row(
          children: [
            const Icon(Icons.grid_4x4, color: Colors.white30, size: 18),
            const SizedBox(width: 8),
            Text(
              'Scanning 8×8 grid…',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
            ),
            const Spacer(),
            if (!_modelReady)
              Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      color: Colors.white24,
                      strokeWidth: 1.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Loading model',
                    style: GoogleFonts.inter(
                      color: Colors.white24,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Point the camera at any waste object.\nDetection works across the entire frame.',
          style: GoogleFonts.inter(
            color: Colors.white24,
            fontSize: 12,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  /// Panel content when waste has been detected (mapped or unmapped).
  Widget _buildDetectionContent(Color accent) {
    final gridPos = _activePosition;
    final cmd = _wasteLocation.robotCommand;
    final dist = _wasteLocation.estimatedDistanceCm;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pull handle
        Center(
          child: Container(
            width: 36,
            height: 3,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // ── Row 1: Detection name + grid coordinate badge ────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Detected label + confidence
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _detectedLabel,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(_confidence * 100).toStringAsFixed(1)}% confidence',
                    style: GoogleFonts.inter(
                      color: accent.withValues(alpha: 0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // Grid coordinate badge (Cartesian)
            if (gridPos != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '${gridPos.centerX.round()}, ${gridPos.centerY.round()}',
                      style: GoogleFonts.robotoMono(
                        color: accent,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'COORD (X, Y)',
                      style: GoogleFonts.inter(
                        color: accent.withValues(alpha: 0.6),
                        fontSize: 9,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),

        const SizedBox(height: 14),
        Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
        const SizedBox(height: 12),

        // ── Row 2: Bin category + robot command ──────────────────────────
        Row(
          children: [
            // Bin category chip
            if (_state == DetectionState.detected && _detectedBin != null)
              _buildBinChip(accent)
            else
              _buildUnmappedChip(),

            const Spacer(),

            // Robot command + distance
            _buildRobotInfo(cmd, dist, accent),
          ],
        ),
      ],
    );
  }

  Widget _buildBinChip(Color accent) {
    final bin = _detectedBin!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(bin.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(
            bin.name,
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnmappedChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _accentAmber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _accentAmber.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            'Not mapped',
            style: GoogleFonts.inter(
              color: _accentAmber.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRobotInfo(String cmd, double? dist, Color accent) {
    // Colour for command: red=stop, amber=turn, green=straight.
    final cmdColor = cmd.startsWith('STOP')
        ? _accentRed
        : cmd.contains('TURN')
        ? _accentAmber
        : _accentGreen;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          cmd,
          style: GoogleFonts.inter(
            color: cmdColor,
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 0.4,
          ),
        ),
        if (dist != null) ...[
          const SizedBox(height: 2),
          Text(
            '~${dist.toStringAsFixed(0)} cm',
            style: GoogleFonts.robotoMono(color: Colors.white38, fontSize: 11),
          ),
        ],
        // ── Grid & pixel coordinates ─────────────────────────────────────
        if (_state != DetectionState.waiting && _activePosition != null) ...[
          const SizedBox(height: 4),
          Text(
            'px(${_activePosition!.pixelX}, ${_activePosition!.pixelY})',
            style: GoogleFonts.robotoMono(
              color: _accentCyan.withValues(alpha: 0.8),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'cX: ${_activePosition!.centerX.toStringAsFixed(0)}  cY: ${_activePosition!.centerY.toStringAsFixed(0)}',
            style: GoogleFonts.robotoMono(
              color: _accentCyan.withValues(alpha: 0.6),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

// Grid overlay is now provided by Grid8x8Overlay from
// lib/ui/grid_overlay_painter.dart
