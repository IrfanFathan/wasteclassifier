import 'package:flutter/material.dart';

class GridPainter extends CustomPainter {
  final int xCells = 8;
  final int yCells = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final double cellWidth = size.width / xCells;
    final double cellHeight = size.height / yCells;

    final Paint gridPaint = Paint()
      ..color = const Color.fromRGBO(255, 255, 255, 0.15)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final Paint crosshairPaint = Paint()
      ..color = const Color.fromRGBO(255, 255, 255, 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Draw vertical lines
    for (int i = 0; i <= xCells; i++) {
      final double x = i * cellWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Draw horizontal lines
    for (int i = 0; i <= yCells; i++) {
      final double y = i * cellHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw crosshair at exact center
    final Offset center = Offset(size.width / 2, size.height / 2);
    const double crosshairSize = 15.0; // 30px arms total (15px each side)
    
    canvas.drawLine(
      Offset(center.dx - crosshairSize, center.dy),
      Offset(center.dx + crosshairSize, center.dy),
      crosshairPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - crosshairSize),
      Offset(center.dx, center.dy + crosshairSize),
      crosshairPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false; // Grid is static based on size
  }
}
