import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/detection.dart';

/// Overlay that paints bounding boxes and labels for detected objects
/// on top of the camera preview using a [CustomPainter].
class DetectionOverlay extends StatelessWidget {
  /// Current detections to render (already in original frame coordinates).
  final List<Detection> detections;

  /// Actual camera frame dimensions (e.g. 1920x1080).
  final int frameWidth;
  final int frameHeight;

  const DetectionOverlay({
    super.key,
    required this.detections,
    required this.frameWidth,
    required this.frameHeight,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DetectionPainter(
        detections: detections,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _DetectionPainter extends CustomPainter {
  final List<Detection> detections;
  final int frameWidth;
  final int frameHeight;

  _DetectionPainter({
    required this.detections,
    required this.frameWidth,
    required this.frameHeight,
  });

  // Stable colour palette for up to 10 classes.
  static const _colors = [
    Color(0xFF00E676), // green
    Color(0xFF00B0FF), // cyan
    Color(0xFFFF5252), // red
    Color(0xFFFFD740), // amber
    Color(0xFFE040FB), // purple
    Color(0xFF18FFFF), // teal
    Color(0xFFFF6E40), // deep orange
    Color(0xFF69F0AE), // light green
    Color(0xFF40C4FF), // light blue
    Color(0xFFFF4081), // pink
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty || frameWidth <= 0 || frameHeight <= 0) return;

    final scaleX = size.width / frameWidth;
    final scaleY = size.height / frameHeight;

    // Track labels for consistent colouring across a frame.
    final labelColors = <String, Color>{};
    int colorIdx = 0;

    for (final det in detections) {
      final color = labelColors.putIfAbsent(det.label, () {
        return _colors[colorIdx++ % _colors.length];
      });

      // Scale box to overlay coordinates
      final left = det.box.left * scaleX;
      final top = det.box.top * scaleY;
      final right = det.box.right * scaleX;
      final bottom = det.box.bottom * scaleY;
      final rect = Rect.fromLTRB(left, top, right, bottom);

      // Draw box fill (semi-transparent)
      final fillPaint = Paint()
        ..color = color.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        fillPaint,
      );

      // Draw box border
      final borderPaint = Paint()
        ..color = color.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        borderPaint,
      );

      // Draw label badge
      final labelText = '${det.label} ${(det.confidence * 100).toStringAsFixed(0)}%';
      final textStyle = ui.TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      );
      final paragraphBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(textAlign: TextAlign.left, maxLines: 1),
      )
        ..pushStyle(textStyle)
        ..addText(labelText);
      final paragraph = paragraphBuilder.build()
        ..layout(ui.ParagraphConstraints(width: size.width));

      final textWidth = min(paragraph.maxIntrinsicWidth + 12, size.width);
      final textHeight = paragraph.height + 6;

      // Position badge above the box
      final badgeLeft = left;
      final badgeTop = max(0.0, top - textHeight - 2);

      // Badge background
      final badgePaint = Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(badgeLeft, badgeTop, textWidth, textHeight),
          const Radius.circular(4),
        ),
        badgePaint,
      );

      // Badge text
      canvas.drawParagraph(paragraph, Offset(badgeLeft + 6, badgeTop + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter oldDelegate) {
    return !identical(oldDelegate.detections, detections);
  }
}
