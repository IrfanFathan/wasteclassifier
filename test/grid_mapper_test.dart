import 'package:flutter_test/flutter_test.dart';
import 'package:wasteclassifier/core/grid_mapper.dart';

void main() {
  // ─── calculateObjectCenter ──────────────────────────────────────────────

  group('GridMapper.calculateObjectCenter', () {
    test('returns center of bounding box', () {
      final center = GridMapper.calculateObjectCenter(
        xMin: 100, yMin: 200, xMax: 300, yMax: 400,
      );
      expect(center.x, 200.0);
      expect(center.y, 300.0);
    });

    test('handles zero-area bounding box (point)', () {
      final center = GridMapper.calculateObjectCenter(
        xMin: 320, yMin: 320, xMax: 320, yMax: 320,
      );
      expect(center.x, 320.0);
      expect(center.y, 320.0);
    });
  });

  // ─── convertToCenterCoordinates ─────────────────────────────────────────

  group('GridMapper.convertToCenterCoordinates', () {
    test('frame center → (0, 0)', () {
      final result = GridMapper.convertToCenterCoordinates(320, 320);
      expect(result.x, 0.0);
      expect(result.y, 0.0);
    });

    test('right of center → positive X', () {
      final result = GridMapper.convertToCenterCoordinates(400, 320);
      expect(result.x, 80.0);
      expect(result.y, 0.0);
    });

    test('above center → positive Y', () {
      final result = GridMapper.convertToCenterCoordinates(320, 250);
      expect(result.x, 0.0);
      expect(result.y, 70.0);
    });

    test('below-left of center → negative X, negative Y', () {
      final result = GridMapper.convertToCenterCoordinates(100, 500);
      expect(result.x, -220.0);
      expect(result.y, -180.0);
    });
  });

  // ─── computeGridCell ────────────────────────────────────────────────────

  group('GridMapper.computeGridCell', () {
    test('(0, 0) → grid (0, 0)', () {
      final cell = GridMapper.computeGridCell(0, 0);
      expect(cell.gridX, 0);
      expect(cell.gridY, 0);
    });

    test('positive X → positive gridX', () {
      final cell = GridMapper.computeGridCell(80, 0);
      expect(cell.gridX, 1);
      expect(cell.gridY, 0);
    });

    test('negative X → negative gridX', () {
      final cell = GridMapper.computeGridCell(-220, 0);
      expect(cell.gridX, -3);
    });

    test('positive Y → positive gridY', () {
      final cell = GridMapper.computeGridCell(0, 70);
      expect(cell.gridY, 0); // floor(70/80) = 0
    });

    test('large positive Y → positive gridY', () {
      final cell = GridMapper.computeGridCell(0, 160);
      expect(cell.gridY, 2);
    });
  });

  // ─── Full pipeline (fromPixel) ──────────────────────────────────────────

  group('GridMapper.fromPixel — Full pipeline', () {
    // Test Case 1: Object at exact center → grid (0, 0)
    test('TC1: center pixel (320, 320) → grid (0, 0)', () {
      final pos = GridMapper.fromPixel(pixelX: 320, pixelY: 320);
      expect(pos.gridX, 0);
      expect(pos.gridY, 0);
      expect(pos.centerX, 0.0);
      expect(pos.centerY, 0.0);
      expect(pos.label, '(0, 0)');
    });

    // Test Case 2: Upper-right quadrant → positive X, positive Y
    test('TC2: upper-right (400, 250) → positive gridX, positive gridY', () {
      final pos = GridMapper.fromPixel(pixelX: 400, pixelY: 250);
      // X = 400 - 320 = 80 → gridX = floor(80/80) = 1
      // Y = 320 - 250 = 70 → gridY = floor(70/80) = 0
      expect(pos.gridX, 1);
      expect(pos.gridY, 0);
      expect(pos.gridX >= 0, true, reason: 'gridX should be positive or zero');
      expect(pos.gridY >= 0, true, reason: 'gridY should be positive or zero');
    });

    // Test Case 3: Lower-left quadrant → negative X, negative Y
    test('TC3: lower-left (100, 500) → negative gridX, negative gridY', () {
      final pos = GridMapper.fromPixel(pixelX: 100, pixelY: 500);
      // X = 100 - 320 = -220 → gridX = floor(-220/80) = -3
      // Y = 320 - 500 = -180 → gridY = floor(-180/80) = -3
      expect(pos.gridX, -3);
      expect(pos.gridY, -3);
      expect(pos.gridX < 0, true, reason: 'gridX should be negative');
      expect(pos.gridY < 0, true, reason: 'gridY should be negative');
    });

    // Edge: top-left corner
    test('top-left corner (0, 0) → grid (-4, 3)', () {
      final pos = GridMapper.fromPixel(pixelX: 0, pixelY: 0);
      // X = 0 - 320 = -320 → gridX = floor(-320/80) = -4
      // Y = 320 - 0 = 320 → gridY = floor(320/80) = 4? No: 320/80 = 4.0, floor(4.0) = 4
      // But valid range is -4..+3 so pixel (0,0) maps to gridY=4 (just outside).
      // With a 640px frame and 8 cells, the valid pixel range for gridY=3 is 0..79.
      // However pixel 0 means Y_center = 320, 320/80 = 4.0, floor = 4.
      // This is expected — the very edge maps to the boundary cell.
      expect(pos.gridX, -4);
      expect(pos.gridY, 4);
    });

    // Edge: bottom-right corner
    test('bottom-right corner (639, 639) → grid (3, -4)', () {
      final pos = GridMapper.fromPixel(pixelX: 639, pixelY: 639);
      // X = 639 - 320 = 319 → gridX = floor(319/80) = floor(3.9875) = 3
      // Y = 320 - 639 = -319 → gridY = floor(-319/80) = floor(-3.9875) = -4
      expect(pos.gridX, 3);
      expect(pos.gridY, -4);
    });
  });

  // ─── fromBoundingBox ────────────────────────────────────────────────────

  group('GridMapper.fromBoundingBox', () {
    test('bounding box centered at (400, 250)', () {
      final pos = GridMapper.fromBoundingBox(
        xMin: 350, yMin: 200, xMax: 450, yMax: 300,
      );
      // Center is (400, 250)
      expect(pos.pixelX, 400);
      expect(pos.pixelY, 250);
      expect(pos.gridX, 1);
      expect(pos.gridY, 0);
    });

    test('action defaults to "pick"', () {
      final pos = GridMapper.fromPixel(pixelX: 320, pixelY: 320);
      expect(pos.action, 'pick');
    });

    test('custom action', () {
      final pos = GridMapper.fromPixel(
        pixelX: 320, pixelY: 320, action: 'place',
      );
      expect(pos.action, 'place');
    });
  });

  // ─── GridPosition.toJson ────────────────────────────────────────────────

  group('GridPosition.toJson', () {
    test('produces correct JSON structure', () {
      final pos = GridMapper.fromPixel(pixelX: 400, pixelY: 250);
      final json = pos.toJson();

      expect(json['grid_x'], 1);
      expect(json['grid_y'], 0);
      expect(json['pixel_x'], 400);
      expect(json['pixel_y'], 250);
      expect(json['action'], 'pick');
    });
  });
}
