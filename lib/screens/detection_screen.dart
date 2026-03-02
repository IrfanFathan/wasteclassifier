import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/app_config.dart';
import '../models/bin_category.dart';
import '../utils/config_manager.dart';
import '../utils/image_processor.dart';
import '../utils/model_manager.dart';
import '../utils/waste_locator.dart';
import 'bin_setup_screen.dart';
import 'upload_screen.dart';

// ─── Detection State ──────────────────────────────────────────────────────

/// Represents the three possible detection outcomes.
enum DetectionState { waiting, detected, unmapped }

// ─── Grid Coordinate ──────────────────────────────────────────────────────

/// A cell in the 4×4 camera grid, addressed by column (A–D) and row (1–4).
///
/// The grid maps the camera frame divided into 16 equal zones.
/// Column A is the leftmost; column D is the rightmost.
/// Row 1 is the top; row 4 is the bottom.
class GridCoord {
  /// Column letter: A, B, C, or D (left → right).
  final String col;

  /// Row number: 1–4 (top → bottom).
  final int row;

  const GridCoord(this.col, this.row);

  /// Human-readable coordinate string, e.g. "B3".
  String get label => '$col$row';

  @override
  String toString() => label;
}

/// Converts a normalised [x] (0–1, left→right) and [y] (0–1, top→bottom) into
/// a [GridCoord] within the 4×4 grid.
GridCoord toGridCoord(double x, double y) {
  const cols = ['A', 'B', 'C', 'D'];
  final colIdx = (x * 4).floor().clamp(0, 3);
  final rowIdx = (y * 4).floor().clamp(0, 3);
  return GridCoord(cols[colIdx], rowIdx + 1);
}

// ─── DetectionScreen ──────────────────────────────────────────────────────

/// Main camera screen for waste classification.
///
/// Features:
///   - Full-screen camera preview (correct 4:3 aspect ratio).
///   - 4×4 grid overlay with column labels A–D and row labels 1–4.
///   - Active cell highlight showing where waste is located in frame.
///   - Bottom-anchored result panel showing waste name + grid coordinate.
///   - Robot navigation command from [WasteLocator].
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

  // ─── Detection Result ───────────────────────────────────────────────────
  DetectionState _state = DetectionState.waiting;
  String _detectedLabel = '';
  double _confidence = 0.0;
  BinCategory? _detectedBin;

  // ─── Spatial / Grid ─────────────────────────────────────────────────────
  /// Active grid coordinate where waste was detected (null when waiting).
  GridCoord? _activeCell;

  /// Robot navigation location from [WasteLocator].
  WasteLocation _wasteLocation = WasteLocation.unknown;

  // ─── Animation ───────────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // ── Design tokens ────────────────────────────────────────────────────────
  static const Color _accentGreen = Color(0xFF00E676);
  static const Color _accentAmber = Color(0xFFFFD740);
  static const Color _accentRed   = Color(0xFFFF5252);
  static const Color _panelBg     = Color(0xE6121212); // 90% opaque dark

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
    if (_isProcessing || !_modelReady || _interpreter == null || _config == null) return;
    _isProcessing = true;
    _runInference(image);
  }

  void _runInference(CameraImage image) {
    try {
      final inputFlat  = ImageProcessor.processImage(image);
      final inputBytes = inputFlat.buffer.asUint8List();

      final numClasses   = _labels.length;
      final outputBuffer = List<double>.filled(numClasses, 0.0);
      final output       = [outputBuffer];

      _interpreter!.run(inputBytes, output);

      final probs  = output[0];
      double maxP  = 0.0;
      int    maxI  = 0;
      for (int i = 0; i < probs.length; i++) {
        if (probs[i] > maxP) { maxP = probs[i]; maxI = i; }
      }

      final label = maxI < _labels.length ? _labels[maxI] : 'Unknown';
      _processResult(label, maxP);
    } catch (e) {
      debugPrint('Inference error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Updates detection state + computes grid coordinate + robot navigation.
  void _processResult(String label, double confidence) {
    if (!mounted) return;
    final config = _config!;

    // Below threshold → waiting.
    if (confidence < config.confidenceThreshold) {
      if (_state != DetectionState.waiting) {
        setState(() {
          _state        = DetectionState.waiting;
          _activeCell   = null;
          _wasteLocation = WasteLocation.unknown;
        });
      }
      return;
    }

    // Nothing label → waiting.
    final isNothing = config.nothingLabels
        .any((n) => n.toLowerCase() == label.toLowerCase());
    if (isNothing) {
      if (_state != DetectionState.waiting) {
        setState(() {
          _state        = DetectionState.waiting;
          _activeCell   = null;
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

    // ── Grid coordinate ────────────────────────────────────────────────────
    // Full-frame classifier: use centre of frame (0.5, 0.5) as the nominal
    // position. When upgraded to a detection model, replace with real bbox_cx
    // / frame_width and bbox_cy / frame_height.
    const double normX = 0.5;
    const double normY = 0.5;
    final cell = toGridCoord(normX, normY);

    // ── Robot navigation (WasteLocator) ────────────────────────────────────
    final location = WasteLocator.compute(
      confidence: confidence,
      frameWidthFraction: normX,
      minConfidence: config.confidenceThreshold,
    );

    setState(() {
      _detectedLabel  = label;
      _confidence     = confidence;
      _activeCell     = cell;
      _wasteLocation  = location;

      if (matchedBin != null) {
        _state       = DetectionState.detected;
        _detectedBin = matchedBin;
      } else {
        _state       = DetectionState.unmapped;
        _detectedBin = null;
      }
    });
  }

  // ─── Settings ────────────────────────────────────────────────────────────

  Future<void> _confirmChangeModel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Change Model',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
        content: Text(
          'This will clear your model and all bin settings. Continue?',
          style: GoogleFonts.inter(color: Colors.white60),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Clear & Change',
                style: GoogleFonts.inter(color: _accentRed, fontWeight: FontWeight.w600)),
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_cameraError != null) return _buildErrorView();
    if (!_cameraReady || _cameraController == null) return _buildLoadingView();

    // Determine accent colour from current state.
    final accent = _stateAccent();

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── 1. Full-screen camera preview ───────────────────────────────
        Positioned.fill(
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: AspectRatio(
              // Use the camera's reported aspect ratio directly (width/height).
              // On Android this is ~0.75 in portrait, giving the correct 3:4
              // portrait representation of a 4:3 sensor.
              aspectRatio: _cameraController!.value.aspectRatio,
              child: CameraPreview(_cameraController!),
            ),
          ),
        ),

        // ── 2. 4×4 Grid overlay ─────────────────────────────────────────
        Positioned.fill(
          child: _Grid4x4Overlay(
            activeCell: _activeCell,
            accentColor: accent,
            pulseAnimation: _pulseAnim,
          ),
        ),

        // ── 3. Status badge (top-left) ──────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          child: _buildStatusBadge(accent),
        ),

        // ── 4. Action buttons (top-right) ───────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          right: MediaQuery.of(context).padding.right + 16,
          child: _buildActionButtons(),
        ),

        // ── 5. Bottom result panel ──────────────────────────────────────
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
      DetectionState.detected  => _detectedBin != null
          ? Color(_detectedBin!.colorHex) : _accentGreen,
      DetectionState.unmapped  => _accentAmber,
      DetectionState.waiting   => Colors.white38,
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
          Text('Initialising camera…',
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 14)),
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
            Icon(Icons.videocam_off_outlined, size: 56, color: _accentRed.withValues(alpha: 0.8)),
            const SizedBox(height: 16),
            Text(_cameraError!,
                style: GoogleFonts.inter(color: Colors.white60, fontSize: 14),
                textAlign: TextAlign.center),
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
              'Scanning 4×4 grid…',
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
                      color: Colors.white24, strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 6),
                  Text('Loading model',
                      style: GoogleFonts.inter(color: Colors.white24, fontSize: 11)),
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
    final cell = _activeCell;
    final cmd  = _wasteLocation.robotCommand;
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

            // Grid coordinate badge
            if (cell != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                      cell.label,
                      style: GoogleFonts.robotoMono(
                        color: accent,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'GRID',
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
        : cmd.contains('TURN') ? _accentAmber : _accentGreen;

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
            style: GoogleFonts.robotoMono(
              color: Colors.white38,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── 4×4 Grid Overlay ────────────────────────────────────────────────────

/// Draws a 4×4 grid over the camera preview with column labels (A–D) along
/// the top, row labels (1–4) along the left side, and optionally highlights
/// one active cell with a pulsing tinted overlay.
class _Grid4x4Overlay extends StatelessWidget {
  const _Grid4x4Overlay({
    required this.activeCell,
    required this.accentColor,
    required this.pulseAnimation,
  });

  /// The cell to highlight; null when nothing is detected.
  final GridCoord? activeCell;

  /// Accent colour used for the active cell and label highlights.
  final Color accentColor;

  /// Drives the pulsing alpha of the active cell highlight.
  final Animation<double> pulseAnimation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, _) {
        return CustomPaint(
          painter: _Grid4x4Painter(
            activeCell: activeCell,
            accentColor: accentColor,
            pulseValue: pulseAnimation.value,
          ),
        );
      },
    );
  }
}

// ─── Grid Painter ─────────────────────────────────────────────────────────

class _Grid4x4Painter extends CustomPainter {
  final GridCoord? activeCell;
  final Color accentColor;
  final double pulseValue;

  static const List<String> _cols = ['A', 'B', 'C', 'D'];
  static const List<String> _rows = ['1', '2', '3', '4'];

  const _Grid4x4Painter({
    required this.activeCell,
    required this.accentColor,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cellW = size.width / 4;
    final double cellH = size.height / 4;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    // ── Draw active cell highlight ────────────────────────────────────────
    if (activeCell != null) {
      final col = _cols.indexOf(activeCell!.col);
      final row = activeCell!.row - 1;

      if (col >= 0 && col < 4 && row >= 0 && row < 4) {
        final cellRect = Rect.fromLTWH(
          col * cellW,
          row * cellH,
          cellW,
          cellH,
        );

        // Filled highlight (pulsing alpha).
        canvas.drawRect(
          cellRect,
          Paint()
            ..color = accentColor.withValues(alpha: 0.18 * pulseValue)
            ..style = PaintingStyle.fill,
        );

        // Border of the active cell.
        canvas.drawRect(
          cellRect,
          Paint()
            ..color = accentColor.withValues(alpha: 0.7)
            ..strokeWidth = 1.8
            ..style = PaintingStyle.stroke,
        );

        // Corner brackets inside the active cell.
        _drawCornerBrackets(canvas, cellRect, accentColor, 10.0, 2.0);
      }
    }

    // ── Draw grid lines ───────────────────────────────────────────────────
    // Vertical lines (skip 0 and 4 — those are the edges).
    for (int c = 1; c < 4; c++) {
      canvas.drawLine(
        Offset(c * cellW, 0),
        Offset(c * cellW, size.height),
        gridPaint,
      );
    }
    // Horizontal lines.
    for (int r = 1; r < 4; r++) {
      canvas.drawLine(
        Offset(0, r * cellH),
        Offset(size.width, r * cellH),
        gridPaint,
      );
    }

    // ── Draw column labels (A B C D) at top ───────────────────────────────
    for (int c = 0; c < 4; c++) {
      final isActiveCol = activeCell != null && _cols[c] == activeCell!.col;
      _drawLabel(
        canvas,
        text: _cols[c],
        x: c * cellW + cellW / 2,
        y: 6,
        color: isActiveCol
            ? accentColor.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.35),
        fontSize: 10,
        bold: isActiveCol,
      );
    }

    // ── Draw row labels (1 2 3 4) on left ────────────────────────────────
    for (int r = 0; r < 4; r++) {
      final isActiveRow = activeCell != null && (r + 1) == activeCell!.row;
      _drawLabel(
        canvas,
        text: _rows[r],
        x: 8,
        y: r * cellH + cellH / 2,
        color: isActiveRow
            ? accentColor.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.35),
        fontSize: 10,
        bold: isActiveRow,
      );
    }
  }

  /// Draws a text label centred at (x, y) on the canvas.
  void _drawLabel(
    Canvas canvas, {
    required String text,
    required double x,
    required double y,
    required Color color,
    double fontSize = 10,
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          fontFamily: 'RobotoMono',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(
      canvas,
      Offset(x - painter.width / 2, y - painter.height / 2),
    );
  }

  /// Draws small L-shaped corner brackets inside [rect].
  void _drawCornerBrackets(
    Canvas canvas,
    Rect rect,
    Color color,
    double length,
    double strokeWidth,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final l  = length;
    final tl = rect.topLeft;
    final tr = rect.topRight;
    final bl = rect.bottomLeft;
    final br = rect.bottomRight;

    // Top-left
    canvas.drawLine(tl, tl + Offset(l, 0), paint);
    canvas.drawLine(tl, tl + Offset(0, l), paint);
    // Top-right
    canvas.drawLine(tr, tr + Offset(-l, 0), paint);
    canvas.drawLine(tr, tr + Offset(0, l), paint);
    // Bottom-left
    canvas.drawLine(bl, bl + Offset(l, 0), paint);
    canvas.drawLine(bl, bl + Offset(0, -l), paint);
    // Bottom-right
    canvas.drawLine(br, br + Offset(-l, 0), paint);
    canvas.drawLine(br, br + Offset(0, -l), paint);
  }

  @override
  bool shouldRepaint(_Grid4x4Painter old) =>
      old.activeCell?.label != activeCell?.label ||
      old.accentColor != accentColor ||
      old.pulseValue != pulseValue;
}
