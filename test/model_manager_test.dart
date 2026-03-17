import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:wasteclassifier/utils/model_manager.dart';

// ─── path_provider fake ───────────────────────────────────────────────────────

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;

  // Required stubs — other methods are not exercised by these tests.
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
  @override
  Future<String?> getApplicationSupportPath() async => tempDir.path;
  @override
  Future<String?> getLibraryPath() async => tempDir.path;
  @override
  Future<String?> getExternalStoragePath() async => tempDir.path;
  @override
  Future<List<String>?> getExternalCachePaths() async => [tempDir.path];
  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async => [tempDir.path];
  @override
  Future<String?> getDownloadsPath() async => tempDir.path;
}

// ─── Test helper ─────────────────────────────────────────────────────────────

/// Write [content] to labels.txt in [dir] and parse it.
Future<List<String>> _parseLabels(Directory dir, String content) async {
  final file = File(p.join(dir.path, 'labels.txt'));
  await file.writeAsString(content);
  return ModelManager.parseLabelsFile();
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_manager_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  // ─── parseLabelsFile: LF line endings ──────────────────────────────────────

  group('ModelManager.parseLabelsFile — LF line endings', () {
    test(
      'indexed format (Teachable Machine) strips leading index numbers',
      () async {
        const content = '0 plastic\n1 metal\n2 glass\n';
        final labels = await _parseLabels(tempDir, content);
        expect(labels, ['plastic', 'metal', 'glass']);
      },
    );

    test('plain format (one name per line) is returned as-is', () async {
      const content = 'aerosol_can\nbattery\ncardboard\n';
      final labels = await _parseLabels(tempDir, content);
      expect(labels, ['aerosol_can', 'battery', 'cardboard']);
    });
  });

  // ─── parseLabelsFile: CRLF line endings ────────────────────────────────────

  group('ModelManager.parseLabelsFile — CRLF line endings', () {
    test('CRLF endings do not produce \\r suffix on labels', () async {
      // Write raw bytes to guarantee CRLF (Windows) line endings.
      final file = File(p.join(tempDir.path, 'labels.txt'));
      await file.writeAsBytes('0 plastic\r\n1 metal\r\n2 glass\r\n'.codeUnits);
      final labels = await ModelManager.parseLabelsFile();
      expect(labels, ['plastic', 'metal', 'glass']);
      for (final label in labels) {
        expect(
          label.endsWith('\r'),
          isFalse,
          reason: 'label "$label" has trailing \\r',
        );
      }
    });

    test('CR-only endings do not produce \\r suffix', () async {
      final file = File(p.join(tempDir.path, 'labels.txt'));
      await file.writeAsBytes('plastic\rmetal\rglass\r'.codeUnits);
      final labels = await ModelManager.parseLabelsFile();
      expect(labels, ['plastic', 'metal', 'glass']);
    });
  });

  // ─── parseLabelsFile: empty-line filtering ─────────────────────────────────

  group('ModelManager.parseLabelsFile — empty-line filtering', () {
    test('blank lines in the middle are removed', () async {
      const content = 'plastic\n\nmetal\n\nglass\n';
      final labels = await _parseLabels(tempDir, content);
      expect(labels, ['plastic', 'metal', 'glass']);
      expect(labels.length, 3);
    });

    test('leading and trailing blank lines are removed', () async {
      const content = '\n\nplastic\nmetal\n\n';
      final labels = await _parseLabels(tempDir, content);
      expect(labels, ['plastic', 'metal']);
    });

    test('completely empty file returns empty list', () async {
      final labels = await _parseLabels(tempDir, '');
      expect(labels, isEmpty);
    });
  });

  // ─── modelFilesExist ───────────────────────────────────────────────────────

  group('ModelManager.modelFilesExist', () {
    test('returns false when no files are present', () async {
      expect(await ModelManager.modelFilesExist(), isFalse);
    });

    test('returns true when both files are present', () async {
      await File(p.join(tempDir.path, 'model.tflite')).writeAsBytes([0]);
      await File(p.join(tempDir.path, 'labels.txt')).writeAsString('plastic\n');
      expect(await ModelManager.modelFilesExist(), isTrue);
    });

    test('returns false when only model.tflite is present', () async {
      await File(p.join(tempDir.path, 'model.tflite')).writeAsBytes([0]);
      expect(await ModelManager.modelFilesExist(), isFalse);
    });
  });
}
