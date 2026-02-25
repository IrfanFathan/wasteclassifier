import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../utils/config_manager.dart';
import '../utils/model_manager.dart';
import 'bin_setup_screen.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  bool _modelExists = false;
  bool _labelsExist = false;
  bool _loadingModel = false;
  bool _loadingLabels = false;
  bool _proceeding = false;
  String _modelStatus = '';
  String _labelsStatus = '';

  @override
  void initState() {
    super.initState();
    _checkExistingFiles();
  }

  /// On every launch, check if files already exist on disk.
  /// Files are stored in getApplicationDocumentsDirectory() which persists
  /// through app closes and device reboots automatically by the OS.
  Future<void> _checkExistingFiles() async {
    final modelPath = await ModelManager.getModelPath();
    final labelsPath = await ModelManager.getLabelsPath();
    final modelFile = File(modelPath);
    final labelsFile = File(labelsPath);

    if (!mounted) return;
    setState(() {
      _modelExists = modelFile.existsSync();
      _labelsExist = labelsFile.existsSync();
      _modelStatus = _modelExists ? '✅ model.tflite already loaded' : '';
      _labelsStatus = _labelsExist ? '✅ labels.txt already loaded' : '';
    });
  }

  Future<void> _pickModelFile() async {
    setState(() {
      _loadingModel = true;
      _modelStatus = 'Selecting model.tflite…';
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Select model.tflite',
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _loadingModel = false;
          _modelStatus = 'Selection cancelled.';
        });
        return;
      }

      final path = result.files.single.path;
      if (path == null || !path.toLowerCase().endsWith('.tflite')) {
        setState(() {
          _loadingModel = false;
          _modelStatus = '❌ Invalid file — must be a .tflite file.';
        });
        return;
      }

      setState(() => _modelStatus = 'Saving model.tflite…');
      await ModelManager.saveModelFile(path);

      setState(() {
        _modelExists = true;
        _loadingModel = false;
        _modelStatus = '✅ model.tflite saved successfully!';
      });
    } catch (e) {
      setState(() {
        _loadingModel = false;
        _modelStatus = '❌ Error: $e';
      });
    }
  }

  Future<void> _pickLabelsFile() async {
    setState(() {
      _loadingLabels = true;
      _labelsStatus = 'Selecting labels.txt…';
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Select labels.txt',
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _loadingLabels = false;
          _labelsStatus = 'Selection cancelled.';
        });
        return;
      }

      final path = result.files.single.path;
      if (path == null) {
        setState(() {
          _loadingLabels = false;
          _labelsStatus = '❌ Could not read file path.';
        });
        return;
      }

      setState(() => _labelsStatus = 'Parsing and saving labels.txt…');
      await ModelManager.saveLabelsFile(path);

      // Parse and save labels list to SharedPreferences
      final labels = await ModelManager.parseLabelsFile();
      if (labels.isEmpty) {
        setState(() {
          _loadingLabels = false;
          _labelsStatus = '❌ labels.txt appears empty or unreadable.';
        });
        return;
      }

      await ConfigManager.saveLabels(labels);

      setState(() {
        _labelsExist = true;
        _loadingLabels = false;
        _labelsStatus = '✅ labels.txt saved! (${labels.length} classes found)';
      });
    } catch (e) {
      setState(() {
        _loadingLabels = false;
        _labelsStatus = '❌ Error: $e';
      });
    }
  }

  Future<void> _proceed() async {
    if (!_modelExists || !_labelsExist) return;
    setState(() => _proceeding = true);

    await ConfigManager.setModelLoaded(true);
    final labels = await ConfigManager.loadLabels();
    final config = await ConfigManager.loadConfig();

    if (!mounted) return;

    if (config != null && config.bins.isNotEmpty) {
      // Config already exists — go straight to detection
      Navigator.of(context).pushReplacementNamed('/detect');
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BinSetupScreen(labels: labels),
        ),
      );
    }
  }

  Future<void> _removeFile(String type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: Text('Remove $type',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to remove the $type file? '
          'You will need to re-upload it.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (type == 'model.tflite') {
      final path = await ModelManager.getModelPath();
      final f = File(path);
      if (f.existsSync()) await f.delete();
      setState(() {
        _modelExists = false;
        _modelStatus = 'model.tflite removed.';
      });
    } else {
      final path = await ModelManager.getLabelsPath();
      final f = File(path);
      if (f.existsSync()) await f.delete();
      await ConfigManager.saveLabels([]);
      setState(() {
        _labelsExist = false;
        _labelsStatus = 'labels.txt removed.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bothReady = _modelExists && _labelsExist;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── Header ───
                const Center(
                  child: Column(
                    children: [
                      Text(
                        '♻️ Waste Classifier',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Upload your Teachable Machine model files',
                        style:
                            TextStyle(color: Colors.white60, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // ─── Export guide chip ───
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.greenAccent.withValues(alpha: 0.25)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.greenAccent, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Export from Teachable Machine → TensorFlow Lite → Floating Point',
                          style: TextStyle(
                              color: Colors.greenAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ─── File 1: model.tflite ───
                _fileCard(
                  icon: Icons.memory_outlined,
                  title: 'model.tflite',
                  subtitle: 'The TFLite neural network weights file',
                  isLoaded: _modelExists,
                  isLoading: _loadingModel,
                  statusMessage: _modelStatus,
                  onUpload: _loadingModel ? null : _pickModelFile,
                  onRemove: _modelExists
                      ? () => _removeFile('model.tflite')
                      : null,
                ),
                const SizedBox(height: 16),

                // ─── File 2: labels.txt ───
                _fileCard(
                  icon: Icons.label_outline,
                  title: 'labels.txt',
                  subtitle: 'Class names exported alongside your model',
                  isLoaded: _labelsExist,
                  isLoading: _loadingLabels,
                  statusMessage: _labelsStatus,
                  onUpload: _loadingLabels ? null : _pickLabelsFile,
                  onRemove: _labelsExist
                      ? () => _removeFile('labels.txt')
                      : null,
                ),

                const SizedBox(height: 32),

                // ─── Proceed button ───
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed:
                        (bothReady && !_proceeding) ? _proceed : null,
                    icon: _proceeding
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black),
                          )
                        : Icon(
                            bothReady
                                ? Icons.check_circle_outline
                                : Icons.lock_outline,
                            color: Colors.black,
                          ),
                    label: Text(
                      _proceeding
                          ? 'Loading…'
                          : bothReady
                              ? 'Continue → Set Up Bins'
                              : 'Upload both files to continue',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: bothReady
                          ? Colors.greenAccent
                          : Colors.white24,
                      disabledBackgroundColor: Colors.white12,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ─── Persistence note ───
                Center(
                  child: Text(
                    '🔒 Files are stored permanently inside the app.\n'
                    'They will remain even after closing or rebooting.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 11,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isLoaded,
    required bool isLoading,
    required String statusMessage,
    required VoidCallback? onUpload,
    required VoidCallback? onRemove,
  }) {
    final borderColor = isLoaded
        ? Colors.greenAccent.withValues(alpha: 0.5)
        : Colors.white.withValues(alpha: 0.1);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: isLoaded
            ? [
                BoxShadow(
                  color: Colors.greenAccent.withValues(alpha: 0.08),
                  blurRadius: 12,
                  spreadRadius: 1,
                )
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Icon badge
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isLoaded
                      ? Colors.greenAccent.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isLoaded ? Icons.check_circle : icon,
                  color: isLoaded ? Colors.greenAccent : Colors.white54,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isLoaded ? Colors.greenAccent : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isLoaded
                      ? Colors.greenAccent.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isLoaded ? 'Ready' : 'Missing',
                  style: TextStyle(
                    color: isLoaded ? Colors.greenAccent : Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          // Status message
          if (statusMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: statusMessage.startsWith('❌')
                    ? Colors.redAccent.withValues(alpha: 0.08)
                    : statusMessage.startsWith('✅')
                        ? Colors.greenAccent.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusMessage,
                style: TextStyle(
                  color: statusMessage.startsWith('❌')
                      ? Colors.redAccent
                      : statusMessage.startsWith('✅')
                          ? Colors.greenAccent
                          : Colors.white60,
                  fontSize: 12,
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Buttons row
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onUpload,
                  icon: isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : Icon(
                          isLoaded
                              ? Icons.swap_horiz
                              : Icons.upload_file_outlined,
                          size: 16,
                          color: Colors.black,
                        ),
                  label: Text(
                    isLoading
                        ? 'Uploading…'
                        : isLoaded
                            ? 'Replace File'
                            : 'Upload $title',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isLoaded
                        ? Colors.greenAccent.withValues(alpha: 0.75)
                        : Colors.greenAccent,
                    disabledBackgroundColor:
                        Colors.greenAccent.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              if (isLoaded && onRemove != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onRemove,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 12),
                  ),
                  child: const Icon(Icons.delete_outline,
                      color: Colors.redAccent, size: 18),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
