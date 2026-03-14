import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/config_manager.dart';
import '../utils/model_manager.dart';
import 'bin_setup_screen.dart';
import 'detection_screen.dart';

enum _UploadState { idle, loading, success, error }

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Shared file state
  bool _modelExists = false;
  bool _labelsExist = false;

  // ZIP tab state
  _UploadState _zipState = _UploadState.idle;
  String _zipStatus = '';

  // Separate files tab state
  _UploadState _modelState = _UploadState.idle;
  _UploadState _labelsState = _UploadState.idle;
  String _modelStatus = '';
  String _labelsStatus = '';

  static const Color _accentGreen = Color(0xFF00E676);
  static const Color _accentCyan = Color(0xFF00B0FF);

  @override
  void initState() {
    super.initState();
    // Enforce portrait mode for Upload Screen
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _tabController = TabController(length: 2, vsync: this);
    _checkExistingFiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkExistingFiles() async {
    final modelPath = await ModelManager.getModelPath();
    final labelsPath = await ModelManager.getLabelsPath();
    if (!mounted) return;
    final modelExists = File(modelPath).existsSync();
    final labelsExists = File(labelsPath).existsSync();
    setState(() {
      _modelExists = modelExists;
      _labelsExist = labelsExists;
      if (modelExists) _modelStatus = 'Verified on device';
      if (labelsExists) _labelsStatus = 'Verified on device';
      if (modelExists) _modelState = _UploadState.success;
      if (labelsExists) _labelsState = _UploadState.success;
    });
  }

  // ── ZIP upload ─────────────────────────────────────────────────────────────
  Future<void> _uploadZip() async {
    setState(() {
      _zipState = _UploadState.loading;
      _zipStatus = 'Opening file picker…';
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Select .zip file',
      );
      if (result == null || result.files.isEmpty) {
        setState(() {
          _zipState = _UploadState.idle;
          _zipStatus = 'Cancelled.';
        });
        return;
      }
      final path = result.files.single.path;
      if (path == null || !path.toLowerCase().endsWith('.zip')) {
        setState(() {
          _zipState = _UploadState.error;
          _zipStatus = 'Please pick a .zip file.';
        });
        return;
      }
      setState(() => _zipStatus = 'Extracting…');
      final extracted = await ModelManager.extractZip(path);
      if (!extracted.success) {
        setState(() {
          _zipState = _UploadState.error;
          _zipStatus = extracted.error ?? 'Unknown extraction error';
        });
        return;
      }
      setState(() => _zipStatus = 'Parsing labels…');
      final labels = await ModelManager.parseLabelsFile();
      if (labels.isEmpty) {
        setState(() {
          _zipState = _UploadState.error;
          _zipStatus = 'labels.txt is empty or unreadable.';
        });
        return;
      }
      await ConfigManager.saveLabels(labels);
      await ConfigManager.setModelLoaded(true);
      setState(() {
        _zipState = _UploadState.success;
        _modelExists = true;
        _labelsExist = true;
        _zipStatus = 'Ready. ${labels.length} classes mapped.';
      });
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      _navigateNext(labels);
    } catch (e) {
      setState(() {
        _zipState = _UploadState.error;
        _zipStatus = e.toString();
      });
    }
  }

  // ── Separate .tflite upload ────────────────────────────────────────────────
  Future<void> _uploadModelFile() async {
    setState(() {
      _modelState = _UploadState.loading;
      _modelStatus = 'Selecting model.tflite…';
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Select model.tflite',
      );
      if (result == null || result.files.isEmpty) {
        setState(() {
          _modelState = _UploadState.idle;
          _modelStatus = 'Cancelled.';
        });
        return;
      }
      final path = result.files.single.path;
      if (path == null || !path.toLowerCase().endsWith('.tflite')) {
        setState(() {
          _modelState = _UploadState.error;
          _modelStatus = 'Must be a .tflite file.';
        });
        return;
      }
      setState(() => _modelStatus = 'Saving…');
      await ModelManager.saveModelFile(path);
      setState(() {
        _modelState = _UploadState.success;
        _modelExists = true;
        _modelStatus = 'Verified on device';
      });
    } catch (e) {
      setState(() {
        _modelState = _UploadState.error;
        _modelStatus = e.toString();
      });
    }
  }

  // ── Separate labels.txt upload ─────────────────────────────────────────────
  Future<void> _uploadLabelsFile() async {
    setState(() {
      _labelsState = _UploadState.loading;
      _labelsStatus = 'Selecting labels.txt…';
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Select labels.txt',
      );
      if (result == null || result.files.isEmpty) {
        setState(() {
          _labelsState = _UploadState.idle;
          _labelsStatus = 'Cancelled.';
        });
        return;
      }
      final path = result.files.single.path;
      if (path == null) {
        setState(() {
          _labelsState = _UploadState.error;
          _labelsStatus = 'Could not get file path.';
        });
        return;
      }
      setState(() => _labelsStatus = 'Parsing labels…');
      await ModelManager.saveLabelsFile(path);
      final labels = await ModelManager.parseLabelsFile();
      if (labels.isEmpty) {
        setState(() {
          _labelsState = _UploadState.error;
          _labelsStatus = 'No classes found in labels.txt.';
        });
        return;
      }
      await ConfigManager.saveLabels(labels);
      setState(() {
        _labelsState = _UploadState.success;
        _labelsExist = true;
        _labelsStatus =
            '${labels.length} classes: ${labels.take(2).join(', ')}${labels.length > 2 ? '…' : ''}';
      });
    } catch (e) {
      setState(() {
        _labelsState = _UploadState.error;
        _labelsStatus = e.toString();
      });
    }
  }

  void _navigateNext(List<String> labels) async {
    final config = await ConfigManager.loadConfig();
    if (!mounted) return;
    if (config != null && config.bins.isNotEmpty) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DetectionScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => BinSetupScreen(labels: labels)),
      );
    }
  }

  Future<void> _clearFiles() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Remove model files',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'This deletes model.tflite and labels.txt from the app storage.',
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
              'Remove',
              style: GoogleFonts.inter(
                color: const Color(0xFFFF5252),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ModelManager.deleteModelFiles();
    await ConfigManager.saveLabels([]);
    await ConfigManager.setModelLoaded(false);
    setState(() {
      _modelExists = false;
      _labelsExist = false;
      _zipState = _UploadState.idle;
      _zipStatus = '';
      _modelState = _UploadState.idle;
      _labelsState = _UploadState.idle;
      _modelStatus = '';
      _labelsStatus = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Background Glow ────────────────────────────────────────────────
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accentGreen.withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -100,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accentCyan.withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: const SizedBox(),
            ),
          ),

          // ── Content ───────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // ── Header ───────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white10),
                        ),
                        child: const Icon(
                          Icons.recycling,
                          color: _accentGreen,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Model Setup',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 28,
                          letterSpacing: -0.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Upload your Teachable Machine export',
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Tab bar ──────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicatorPadding: const EdgeInsets.all(4),
                      indicator: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white38,
                      labelStyle: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'ZIP Archive'),
                        Tab(text: 'Separate Files'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Tab views ────────────────────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [_buildZipTab(), _buildSeparateTab()],
                  ),
                ),

                // ── Continue / remove buttons ────────────────────────────────
                if (_modelExists && _labelsExist)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: Column(
                      children: [
                        _buildContinueButton(),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: _clearFiles,
                          child: Text(
                            'Remove and start over',
                            style: GoogleFonts.inter(
                              color: const Color(
                                0xFFFF5252,
                              ).withValues(alpha: 0.8),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── ZIP tab ----------------------------------------------------------------
  Widget _buildZipTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        children: [
          _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _accentGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.info_outline,
                        color: _accentGreen,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Instructions',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _infoLine('1. Export Model from Teachable Machine'),
                _infoLine('2. Select "TensorFlow Lite" → "Floating Point"'),
                _infoLine('3. Download the provided .zip file'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _UploadDropzone(
            title: 'Upload ZIP',
            subtitle: 'Includes model.tflite & labels.txt',
            icon: Icons.folder_zip_rounded,
            state: _zipState,
            statusMessage: _zipStatus,
            onTap: _zipState == _UploadState.loading ? null : _uploadZip,
          ),
        ],
      ),
    );
  }

  // ── Separate files tab -----------------------------------------------------
  Widget _buildSeparateTab() {
    final bothReady = _modelExists && _labelsExist;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        children: [
          _UploadDropzone(
            title: 'model.tflite',
            subtitle: 'Neural network weights',
            icon: Icons.memory_rounded,
            state: _modelState,
            statusMessage: _modelStatus,
            onTap: _modelState == _UploadState.loading
                ? null
                : _uploadModelFile,
          ),
          const SizedBox(height: 16),
          _UploadDropzone(
            title: 'labels.txt',
            subtitle: 'Class names list',
            icon: Icons.label_rounded,
            state: _labelsState,
            statusMessage: _labelsStatus,
            onTap: _labelsState == _UploadState.loading
                ? null
                : _uploadLabelsFile,
          ),
          const SizedBox(height: 24),
          if (!bothReady)
            Text(
              'Both files are required to proceed.',
              style: GoogleFonts.inter(
                color: Colors.white38,
                fontSize: 13,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _infoLine(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4, right: 12),
          child: Icon(Icons.circle, color: Colors.white24, size: 6),
        ),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildContinueButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00E676), Color(0xFF1DE9B6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E676).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final labels = await ConfigManager.loadLabels();
            if (!mounted) return;
            _navigateNext(labels);
          },
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Continue to Configuration',
                  style: GoogleFonts.inter(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.black87,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Glass Components ───────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final Widget child;

  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _UploadDropzone extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final _UploadState state;
  final String statusMessage;
  final VoidCallback? onTap;

  const _UploadDropzone({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.state,
    required this.statusMessage,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSuccess = state == _UploadState.success;
    final isError = state == _UploadState.error;
    final isLoading = state == _UploadState.loading;

    final borderColor = isSuccess
        ? const Color(0xFF00E676).withValues(alpha: 0.5)
        : isError
        ? const Color(0xFFFF5252).withValues(alpha: 0.5)
        : Colors.white10;

    final bgColor = isSuccess
        ? const Color(0xFF00E676).withValues(alpha: 0.05)
        : isError
        ? const Color(0xFFFF5252).withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.03);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isSuccess
                            ? const Color(0xFF00E676).withValues(alpha: 0.1)
                            : isError
                            ? const Color(0xFFFF5252).withValues(alpha: 0.1)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor),
                      ),
                      child: isLoading
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              isSuccess ? Icons.check_rounded : icon,
                              color: isSuccess
                                  ? const Color(0xFF00E676)
                                  : isError
                                  ? const Color(0xFFFF5252)
                                  : Colors.white70,
                              size: 24,
                            ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: GoogleFonts.inter(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isSuccess && !isLoading)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Browse',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                if (statusMessage.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isError ? Icons.error_outline : Icons.info_outline,
                          color: isError
                              ? const Color(0xFFFF5252)
                              : Colors.white54,
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            statusMessage,
                            style: GoogleFonts.inter(
                              color: isError
                                  ? const Color(0xFFFF5252)
                                  : Colors.white70,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
