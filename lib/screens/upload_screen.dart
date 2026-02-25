import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/config_manager.dart';
import '../utils/model_manager.dart';
import 'bin_setup_screen.dart';

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

  @override
  void initState() {
    super.initState();
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
      if (modelExists) _modelStatus = '✅ model.tflite already on device';
      if (labelsExists) _labelsStatus = '✅ labels.txt already on device';
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
      final result = await FilePicker.platform
          .pickFiles(type: FileType.any, dialogTitle: 'Select .zip file');
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
          _zipStatus = '❌ Please pick a .zip file.';
        });
        return;
      }
      setState(() => _zipStatus = 'Extracting…');
      final extracted = await ModelManager.extractZip(path);
      if (!extracted.success) {
        setState(() {
          _zipState = _UploadState.error;
          _zipStatus = '❌ ${extracted.error}';
        });
        return;
      }
      setState(() => _zipStatus = 'Parsing labels…');
      final labels = await ModelManager.parseLabelsFile();
      if (labels.isEmpty) {
        setState(() {
          _zipState = _UploadState.error;
          _zipStatus = '❌ labels.txt is empty or unreadable.';
        });
        return;
      }
      await ConfigManager.saveLabels(labels);
      await ConfigManager.setModelLoaded(true);
      setState(() {
        _zipState = _UploadState.success;
        _modelExists = true;
        _labelsExist = true;
        _zipStatus =
            '✅ Extracted ${labels.length} classes: ${labels.take(3).join(', ')}${labels.length > 3 ? '…' : ''}';
      });
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      _navigateNext(labels);
    } catch (e) {
      setState(() {
        _zipState = _UploadState.error;
        _zipStatus = '❌ $e';
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
      final result = await FilePicker.platform
          .pickFiles(type: FileType.any, dialogTitle: 'Select model.tflite');
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
          _modelStatus = '❌ Must be a .tflite file.';
        });
        return;
      }
      setState(() => _modelStatus = 'Saving…');
      await ModelManager.saveModelFile(path);
      setState(() {
        _modelState = _UploadState.success;
        _modelExists = true;
        _modelStatus = '✅ model.tflite saved!';
      });
    } catch (e) {
      setState(() {
        _modelState = _UploadState.error;
        _modelStatus = '❌ $e';
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
      final result = await FilePicker.platform
          .pickFiles(type: FileType.any, dialogTitle: 'Select labels.txt');
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
          _labelsStatus = '❌ Could not get file path.';
        });
        return;
      }
      setState(() => _labelsStatus = 'Parsing labels…');
      await ModelManager.saveLabelsFile(path);
      final labels = await ModelManager.parseLabelsFile();
      if (labels.isEmpty) {
        setState(() {
          _labelsState = _UploadState.error;
          _labelsStatus = '❌ No classes found in labels.txt.';
        });
        return;
      }
      await ConfigManager.saveLabels(labels);
      setState(() {
        _labelsState = _UploadState.success;
        _labelsExist = true;
        _labelsStatus =
            '✅ ${labels.length} classes: ${labels.take(3).join(', ')}${labels.length > 3 ? '…' : ''}';
      });
    } catch (e) {
      setState(() {
        _labelsState = _UploadState.error;
        _labelsStatus = '❌ $e';
      });
    }
  }


  void _navigateNext(List<String> labels) async {
    final config = await ConfigManager.loadConfig();
    if (!mounted) return;
    if (config != null && config.bins.isNotEmpty) {
      Navigator.of(context).pushReplacementNamed('/detect');
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
        backgroundColor: Colors.white,
        title: const Text('Remove model files',
            style: TextStyle(color: Color(0xFF08090E))),
        content: const Text(
          'This deletes model.tflite and labels.txt from the app storage.',
          style: TextStyle(color: Color(0xFF727067))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF727067))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Color(0xFFC62828))),
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                children: [
                  Text('♻️ Waste Classifier',
                      style: GoogleFonts.inter(
                          color: const Color(0xFF08090E),
                          fontSize: 26,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Upload your Teachable Machine model',
                      style: GoogleFonts.inter(
                          color: const Color(0xFF727067),
                          fontSize: 13)),
                ],
              ),
            ),

            // ── File status row ──────────────────────────────────────────────
            if (_modelExists || _labelsExist)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _StatusChip(
                        label: 'model.tflite', found: _modelExists),
                    const SizedBox(width: 8),
                    _StatusChip(
                        label: 'labels.txt', found: _labelsExist),
                  ],
                ),
              ),

            if (_modelExists || _labelsExist) const SizedBox(height: 12),

            // ── Tab bar ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFABA69E), width: 0.5),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: const Color(0xFF08090E),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: const Color(0xFF727067),
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: '📦  Upload ZIP'),
                    Tab(text: '📂  Separate Files'),
                  ],
                ),
              ),
            ),

            // ── Tab views ───────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildZipTab(),
                  _buildSeparateTab(),
                ],
              ),
            ),

            // ── Continue / remove buttons ────────────────────────────────────
            if (_modelExists && _labelsExist)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final labels = await ConfigManager.loadLabels();
                          if (!mounted) return;
                          _navigateNext(labels);
                        },
                        icon: const Icon(Icons.arrow_forward,
                            color: Colors.white, size: 18),
                        label: const Text('Continue → Set Up Bins',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _clearFiles,
                      icon: const Icon(Icons.delete_outline,
                          color: Color(0xFFC62828), size: 15),
                      label: const Text('Remove all files',
                          style:
                              TextStyle(color: Color(0xFFC62828), fontSize: 13)),
                    ),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '🔒 Files persist after close or reboot',
                style: TextStyle(
                    color: const Color(0xFFABA69E),
                    fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── ZIP tab ----------------------------------------------------------------
  Widget _buildZipTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Animated icon
          AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _zipState == _UploadState.success
                    ? const Color(0xFF08090E)
                    : _zipState == _UploadState.error
                        ? const Color(0xFFC62828)
                        : const Color(0xFFABA69E),
                width: 1,
              ),
            ),
            child: Center(
              child: _zipState == _UploadState.loading
                  ? const CircularProgressIndicator(
                      color: Color(0xFF08090E), strokeWidth: 3)
                  : Icon(
                      _zipState == _UploadState.success
                          ? Icons.check_circle_outline
                          : _zipState == _UploadState.error
                              ? Icons.error_outline
                              : Icons.folder_zip_outlined,
                      color: _zipState == _UploadState.success
                          ? const Color(0xFF08090E)
                          : _zipState == _UploadState.error
                              ? const Color(0xFFC62828)
                              : const Color(0xFF727067),
                      size: 48,
                    ),
            ),
          ),
          const SizedBox(height: 20),

          // Info card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFABA69E), width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Teachable Machine export steps:',
                    style: TextStyle(
                        color: Color(0xFF08090E),
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 8),
                _infoLine('Export Model → TensorFlow Lite → Floating Point'),
                _infoLine('Download the .zip — it includes both files'),
                _infoLine('Tap below to pick the .zip'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Upload button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _zipState == _UploadState.loading ? null : _uploadZip,
              icon: _zipState == _UploadState.loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.folder_zip_outlined,
                      color: Colors.white, size: 20),
              label: Text(
                _zipState == _UploadState.loading
                    ? _zipStatus
                    : '  Pick .zip File',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14),
              ),
            ),
          ),

          // Status
          if (_zipStatus.isNotEmpty && _zipState != _UploadState.loading) ...[
            const SizedBox(height: 14),
            _StatusCard(message: _zipStatus, state: _zipState),
          ],
        ],
      ),
    );
  }

  // ── Separate files tab -----------------------------------------------------
  Widget _buildSeparateTab() {
    final bothReady = _modelExists && _labelsExist;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // model.tflite card
          _FileUploadCard(
            icon: Icons.memory_outlined,
            title: 'model.tflite',
            subtitle: 'Neural network weights file',
            state: _modelState,
            statusMessage: _modelStatus,
            buttonLabel: _modelExists ? 'Replace model.tflite' : 'Pick model.tflite',
            onPick: _modelState == _UploadState.loading ? null : _uploadModelFile,
          ),
          const SizedBox(height: 14),
          // labels.txt card
          _FileUploadCard(
            icon: Icons.label_outline,
            title: 'labels.txt',
            subtitle: 'Class names exported from your model',
            state: _labelsState,
            statusMessage: _labelsStatus,
            buttonLabel: _labelsExists ? 'Replace labels.txt' : 'Pick labels.txt',
            onPick: _labelsState == _UploadState.loading ? null : _uploadLabelsFile,
          ),
          const SizedBox(height: 20),

          if (!bothReady)
            const Text(
              'Upload both files to enable the Continue button below',
              style: TextStyle(
                  color: Color(0xFF727067),
                  fontSize: 12,
                  height: 1.5),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _infoLine(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• ',
                style: TextStyle(color: Color(0xFF08090E), fontSize: 13)),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: Color(0xFF727067),
                      fontSize: 13,
                      height: 1.4)),
            ),
          ],
        ),
      );

  bool get _labelsExists => _labelsExist;
}

// ── Reusable widgets ─────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String label;
  final bool found;
  const _StatusChip({required this.label, required this.found});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: found
              ? const Color(0xFF08090E).withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: found
                  ? const Color(0xFF08090E).withValues(alpha: 0.2)
                  : const Color(0xFFABA69E)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              found ? Icons.check_circle : Icons.radio_button_unchecked,
              color: found ? const Color(0xFF08090E) : const Color(0xFFABA69E),
              size: 14,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  style: TextStyle(
                      color: found ? const Color(0xFF08090E) : const Color(0xFF727067),
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String message;
  final _UploadState state;
  const _StatusCard({required this.message, required this.state});

  @override
  Widget build(BuildContext context) {
    final isSuccess = state == _UploadState.success;
    final isError = state == _UploadState.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isSuccess
            ? const Color(0xFF08090E).withValues(alpha: 0.05)
            : isError
                ? const Color(0xFFC62828).withValues(alpha: 0.08)
                : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isSuccess
                ? const Color(0xFF08090E).withValues(alpha: 0.2)
                : isError
                    ? const Color(0xFFC62828).withValues(alpha: 0.3)
                    : const Color(0xFFABA69E)),
      ),
      child: Text(message,
          style: TextStyle(
              color: isSuccess
                  ? const Color(0xFF08090E)
                  : isError
                      ? const Color(0xFFC62828)
                      : const Color(0xFF727067),
              fontSize: 12,
              height: 1.5)),
    );
  }
}

class _FileUploadCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final _UploadState state;
  final String statusMessage;
  final String buttonLabel;
  final VoidCallback? onPick;

  const _FileUploadCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.state,
    required this.statusMessage,
    required this.buttonLabel,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final isReady = state == _UploadState.success;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isReady
              ? const Color(0xFF08090E).withValues(alpha: 0.3)
              : const Color(0xFFABA69E),
          width: isReady ? 1.5 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isReady
                      ? const Color(0xFF08090E).withValues(alpha: 0.05)
                      : Colors.transparent,
                  border: isReady ? null : Border.all(color: const Color(0xFFABA69E), width: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isReady ? Icons.check_circle : icon,
                  color: isReady ? const Color(0xFF08090E) : const Color(0xFFABA69E),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Color(0xFF08090E),
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Color(0xFF727067),
                            fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isReady
                      ? const Color(0xFF08090E).withValues(alpha: 0.1)
                      : Colors.transparent,
                  border: isReady ? null : Border.all(color: const Color(0xFFABA69E), width: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isReady ? 'Ready' : 'Missing',
                  style: TextStyle(
                      color: isReady ? const Color(0xFF08090E) : const Color(0xFFABA69E),
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (statusMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            _StatusCard(message: statusMessage, state: state),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              onPressed: onPick,
              icon: state == _UploadState.loading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: isReady ? const Color(0xFF08090E) : Colors.white))
                  : Icon(
                      isReady ? Icons.swap_horiz : Icons.upload_file_outlined,
                      color: isReady ? const Color(0xFF08090E) : Colors.white,
                      size: 16),
              label: Text(
                state == _UploadState.loading ? 'Uploading…' : buttonLabel,
                style: TextStyle(
                    color: isReady ? const Color(0xFF08090E) : Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isReady
                    ? const Color(0xFF08090E).withValues(alpha: 0.05)
                    : const Color(0xFF08090E),
                elevation: isReady ? 0 : 1,
                disabledBackgroundColor:
                    const Color(0xFF08090E).withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                side: isReady ? BorderSide(color: const Color(0xFF08090E).withValues(alpha: 0.2)) : BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
