import 'package:flutter/material.dart';

class GridPainter extends CustomPainter {
  final int xCells = 8;
  final int yCells = 8;
  final Color lineColor;
  final double lineWidth;

  GridPainter({
    this.lineColor = const Color.fromRGBO(255, 255, 255, 0.4),
    this.lineWidth = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Define standard line paint
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = lineWidth
      ..style = PaintingStyle.stroke;

    final double cellWidth = size.width / xCells;
    final double cellHeight = size.height / yCells;

    // Draw internal vertical lines
    for (int i = 1; i < xCells; i++) {
      final double dx = i * cellWidth;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), linePaint);
    }

    // Draw internal horizontal lines
    for (int i = 1; i < yCells; i++) {
      final double dy = i * cellHeight;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), linePaint);
    }
    
    // 2. Draw outer boundary box (Matches exactly the perimeter of the screen)
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), linePaint);

    // 3. Optional: Draw a precise center crosshair
    final centerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    const crosshairSize = 12.0;
    
    canvas.drawLine(Offset(centerX - crosshairSize, centerY), Offset(centerX + crosshairSize, centerY), centerPaint);
    canvas.drawLine(Offset(centerX, centerY - crosshairSize), Offset(centerX, centerY + crosshairSize), centerPaint);
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
           oldDelegate.lineWidth != lineWidth;
  }
}
