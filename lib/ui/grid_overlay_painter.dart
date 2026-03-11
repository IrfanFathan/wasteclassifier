/// grid_overlay_painter.dart
///
/// Draws an 8×8 center-origin grid overlay on the camera preview.
///
/// Features:
///   - 8×8 grid lines
///   - Center crosshair marking the origin (0, 0)
///   - Axis labels: −4 to +3 on both axes
///   - Active cell highlight with pulsing animation
///   - Detected object position marker
library;

import 'package:flutter/material.dart';
import '../core/grid_mapper.dart';

// ─── Grid Overlay Widget ──────────────────────────────────────────────────

/// Stateless widget that wraps the [Grid8x8Painter] with pulse animation.
class Grid8x8Overlay extends StatelessWidget {
  const Grid8x8Overlay({
    super.key,
    required this.activePosition,
    required this.accentColor,
    required this.pulseAnimation,
  });

  /// The grid position to highlight; null when nothing is detected.
  final GridPosition? activePosition;

  /// Accent colour used for highlights.
  final Color accentColor;

  /// Drives the pulsing alpha of the active cell.
  final Animation<double> pulseAnimation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, _) {
        return CustomPaint(
          painter: Grid8x8Painter(
            activePosition: activePosition,
            accentColor: accentColor,
            pulseValue: pulseAnimation.value,
          ),
        );
      },
    );
  }
}

// ─── Grid Painter ─────────────────────────────────────────────────────────

/// Custom painter that renders the 8×8 center-origin grid.
class Grid8x8Painter extends CustomPainter {
  final GridPosition? activePosition;
  final Color accentColor;
  final double pulseValue;

  /// Grid axis labels: columns −4 to +3 (left → right).
  static const List<int> _colLabels = [-4, -3, -2, -1, 0, 1, 2, 3];

  /// Grid axis labels: rows +3 to −4 (top → bottom) — Y-up convention.
  static const List<int> _rowLabels = [3, 2, 1, 0, -1, -2, -3, -4];

  const Grid8x8Painter({
    required this.activePosition,
    required this.accentColor,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cellW = size.width / 8;
    final double cellH = size.height / 8;
    final double centerX = size.width / 2;
    final double centerY = size.height / 2;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    // ── Active cell highlight ──────────────────────────────────────────────
    if (activePosition != null) {
      // Convert from grid coordinates to canvas cell.
      // gridX range: −4..+3 → column index 0..7 by adding 4
      // gridY range: +3..−4 → row index 0..7 by subtracting from 3
      final colIdx = (activePosition!.gridX + 4).clamp(0, 7);
      final rowIdx = (3 - activePosition!.gridY).clamp(0, 7);

      final cellRect = Rect.fromLTWH(
        colIdx * cellW,
        rowIdx * cellH,
        cellW,
        cellH,
      );

      // Filled highlight (pulsing alpha).
      canvas.drawRect(
        cellRect,
        Paint()
          ..color = accentColor.withValues(alpha: 0.20 * pulseValue)
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

      // Corner brackets.
      _drawCornerBrackets(canvas, cellRect, accentColor, 10.0, 2.0);
    }

    // ── Grid lines ────────────────────────────────────────────────────────
    for (int c = 1; c < 8; c++) {
      final isCenter = c == 4;
      canvas.drawLine(
        Offset(c * cellW, 0),
        Offset(c * cellW, size.height),
        isCenter ? _centerLinePaint() : gridPaint,
      );
    }
    for (int r = 1; r < 8; r++) {
      final isCenter = r == 4;
      canvas.drawLine(
        Offset(0, r * cellH),
        Offset(size.width, r * cellH),
        isCenter ? _centerLinePaint() : gridPaint,
      );
    }

    // ── Origin marker (small crosshair at center) ─────────────────────────
    final originPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1.2;

    const double markerLen = 8.0;
    canvas.drawLine(
      Offset(centerX - markerLen, centerY),
      Offset(centerX + markerLen, centerY),
      originPaint,
    );
    canvas.drawLine(
      Offset(centerX, centerY - markerLen),
      Offset(centerX, centerY + markerLen),
      originPaint,
    );

    // Small dot at exact center.
    canvas.drawCircle(
      Offset(centerX, centerY),
      2.5,
      Paint()..color = Colors.white.withValues(alpha: 0.8),
    );

    // ── Column labels (X axis: −4 to +3) at top ──────────────────────────
    for (int c = 0; c < 8; c++) {
      final isActiveCol =
          activePosition != null && _colLabels[c] == activePosition!.gridX;
      _drawLabel(
        canvas,
        text: '${_colLabels[c]}',
        x: c * cellW + cellW / 2,
        y: 8,
        color: isActiveCol
            ? accentColor.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.30),
        fontSize: 9,
        bold: isActiveCol,
      );
    }

    // ── Row labels (Y axis: +3 to −4) on left ────────────────────────────
    for (int r = 0; r < 8; r++) {
      final isActiveRow =
          activePosition != null && _rowLabels[r] == activePosition!.gridY;
      _drawLabel(
        canvas,
        text: '${_rowLabels[r]}',
        x: 10,
        y: r * cellH + cellH / 2,
        color: isActiveRow
            ? accentColor.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.30),
        fontSize: 9,
        bold: isActiveRow,
      );
    }

    // ── "X" / "Y" axis indicators near center ─────────────────────────────
    _drawLabel(
      canvas,
      text: 'X',
      x: size.width - 14,
      y: centerY + 12,
      color: Colors.white.withValues(alpha: 0.25),
      fontSize: 9,
      bold: false,
    );
    _drawLabel(
      canvas,
      text: 'Y',
      x: centerX + 12,
      y: 20,
      color: Colors.white.withValues(alpha: 0.25),
      fontSize: 9,
      bold: false,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Paint _centerLinePaint() => Paint()
    ..color = Colors.white.withValues(alpha: 0.25)
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;

  void _drawLabel(
    Canvas canvas, {
    required String text,
    required double x,
    required double y,
    required Color color,
    double fontSize = 9,
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

    final l = length;
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
  bool shouldRepaint(Grid8x8Painter old) =>
      old.activePosition?.label != activePosition?.label ||
      old.accentColor != accentColor ||
      old.pulseValue != pulseValue;
}
