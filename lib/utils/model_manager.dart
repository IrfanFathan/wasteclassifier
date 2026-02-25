import 'dart:io';
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

  /// Parses labels.txt from Teachable Machine format.
  /// Strips leading index numbers like "0 ", "1 " etc.
  static Future<List<String>> parseLabelsFile() async {
    final labelsPath = await getLabelsPath();
    final file = File(labelsPath);
    if (!file.existsSync()) return [];
    final lines = await file.readAsLines();
    return lines.map((line) {
      final trimmed = line.trim();
      // Strip leading index number e.g. "0 PlasticBottle" → "PlasticBottle"
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
