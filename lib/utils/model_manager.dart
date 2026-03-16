import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ModelManager {
  static const _modelFileName = 'model.tflite';
  static const _labelsFileName = 'labels.txt';

  static Future<Directory> _getModelDirectory() async {
    return await getApplicationDocumentsDirectory();
  }

  static Future<String> getModelPath() async {
    final dir = await _getModelDirectory();
    return p.join(dir.path, _modelFileName);
  }

  static Future<String> getLabelsPath() async {
    final dir = await _getModelDirectory();
    return p.join(dir.path, _labelsFileName);
  }

  static Future<bool> modelFilesExist() async {
    final modelPath = await getModelPath();
    final labelsPath = await getLabelsPath();
    return File(modelPath).existsSync() && File(labelsPath).existsSync();
  }

  static Future<void> saveModelFile(String sourcePath) async {
    final destPath = await getModelPath();
    await File(sourcePath).copy(destPath);
  }

  static Future<void> saveLabelsFile(String sourcePath) async {
    final destPath = await getLabelsPath();
    await File(sourcePath).copy(destPath);
  }

  /// Extracts a ZIP file and locates model.tflite + labels.txt inside.
  /// Returns a [ZipExtractResult] describing what was found.
  /// Files are saved to getApplicationDocumentsDirectory() automatically.
  static Future<ZipExtractResult> extractZip(String zipPath) async {
    final zipFile = File(zipPath);
    if (!zipFile.existsSync()) {
      return ZipExtractResult(
          success: false, error: 'ZIP file not found at path.');
    }

    // Read and decode the ZIP archive
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final dir = await _getModelDirectory();
    bool foundModel = false;
    bool foundLabels = false;

    for (final file in archive) {
      if (file.isFile) {
        final name = p.basename(file.name).toLowerCase();
        if (name == 'model.tflite') {
          final destPath = p.join(dir.path, _modelFileName);
          final outFile = File(destPath);
          await outFile.writeAsBytes(file.content as List<int>);
          foundModel = true;
        } else if (name == 'labels.txt') {
          final destPath = p.join(dir.path, _labelsFileName);
          final outFile = File(destPath);
          await outFile.writeAsBytes(file.content as List<int>);
          foundLabels = true;
        }
      }
    }

    if (!foundModel && !foundLabels) {
      return ZipExtractResult(
        success: false,
        error: 'No model.tflite or labels.txt found in the ZIP.\n'
            'Make sure you export "TensorFlow Lite → Floating Point" from Teachable Machine.',
      );
    }
    if (!foundModel) {
      return ZipExtractResult(
          success: false,
          error: 'labels.txt found but model.tflite is missing from the ZIP.');
    }
    if (!foundLabels) {
      return ZipExtractResult(
          success: false,
          error: 'model.tflite found but labels.txt is missing from the ZIP.');
    }

    return ZipExtractResult(success: true);
  }

  /// Parses labels.txt from Teachable Machine format.
  /// Strips leading index numbers like "0 ", "1 " etc.
  static Future<List<String>> parseLabelsFile() async {
    final labelsPath = await getLabelsPath();
    final file = File(labelsPath);
    if (!file.existsSync()) return [];
    final raw = await file.readAsString();
    final lines = raw.split(RegExp(r'\r\n|\r|\n'));
    return lines.map((line) {
      final trimmed = line.trim();
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length > 1 && int.tryParse(parts[0]) != null) {
        return parts.sublist(1).join(' ');
      }
      return trimmed;
    }).where((l) => l.isNotEmpty).toList();
  }

  static Future<void> deleteModelFiles() async {
    final modelPath = await getModelPath();
    final labelsPath = await getLabelsPath();
    final modelFile = File(modelPath);
    final labelsFile = File(labelsPath);
    if (modelFile.existsSync()) await modelFile.delete();
    if (labelsFile.existsSync()) await labelsFile.delete();
  }
}

/// Result returned from [ModelManager.extractZip].
class ZipExtractResult {
  final bool success;
  final String? error;
  const ZipExtractResult({required this.success, this.error});
}
