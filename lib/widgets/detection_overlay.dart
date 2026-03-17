import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/detection.dart';

// ─── Color palette ─────────────────────────────────────────────────────────

const _colors = [
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

Color _colorForLabel(String label, Map<String, int> indexMap) {
  if (!indexMap.containsKey(label)) {
    indexMap[label] = indexMap.length;
  }
  return _colors[indexMap[label]! % _colors.length];
}

// ─── Public widget ─────────────────────────────────────────────────────────

/// Overlay that renders animated bounding boxes and label badges for detected
/// objects on top of the camera preview.
///
/// Each unique label fades **in** over 150 ms and **out** over 300 ms using an
/// [AnimationController] per label so that boxes appear/disappear smoothly
/// rather than snapping on/off.
class DetectionOverlay extends StatefulWidget {
  /// Current detections to render (already in original frame coordinates).
  final List<Detection> detections;

  /// Actual camera frame dimensions (e.g. 1920×1080).
  final int frameWidth;
  final int frameHeight;

  const DetectionOverlay({
    super.key,
    required this.detections,
    required this.frameWidth,
    required this.frameHeight,
  });

  @override
  State<DetectionOverlay> createState() => _DetectionOverlayState();
}

// ─── State ──────────────────────────────────────────────────────────────────

class _DetectionOverlayState extends State<DetectionOverlay>
    with TickerProviderStateMixin {
  // Per-label animation controllers (fade in / fade out).
  final Map<String, AnimationController> _controllers = {};
  // Stable label → color index mapping so colors don't change as detections
  // come and go.
  final Map<String, int> _colorIndex = {};

  // The most-recent detection snapshot keyed by label (used when painting
  // the box during fade-out, after the label has left widget.detections).
  final Map<String, Detection> _lastSeen = {};

  @override
  void didUpdateWidget(DetectionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    final activeLabels = <String>{};
    for (final det in widget.detections) {
      activeLabels.add(det.label);
      _lastSeen[det.label] = det;

      // Ensure a controller exists for this label.
      _controllers.putIfAbsent(det.label, () {
        _colorForLabel(det.label, _colorIndex); // register color slot
        return AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 150),
          reverseDuration: const Duration(milliseconds: 300),
        );
      });

      // Animate to visible.
      final ctrl = _controllers[det.label]!;
      if (!ctrl.isAnimating && ctrl.value < 1.0) {
        ctrl.forward();
      }
    }

    // Fade out labels that have disappeared.
    for (final label in _controllers.keys) {
      if (!activeLabels.contains(label)) {
        final ctrl = _controllers[label]!;
        if (!ctrl.isAnimating && ctrl.value > 0.0) {
          ctrl.reverse();
        }
      }
    }
  }

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.frameWidth <= 0 || widget.frameHeight <= 0) {
      return const SizedBox.expand();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaleX = constraints.maxWidth / widget.frameWidth;
        final scaleY = constraints.maxHeight / widget.frameHeight;

        final boxes = <Widget>[];

        for (final entry in _controllers.entries) {
          final label = entry.key;
          final ctrl = entry.value;
          final det = _lastSeen[label];
          if (det == null) continue;

          final color = _colorForLabel(label, _colorIndex);

          boxes.add(
            AnimatedBuilder(
              animation: ctrl,
              builder: (context, _) {
                final opacity = ctrl.value;
                if (opacity <= 0) return const SizedBox.shrink();

                final left = det.box.left * scaleX;
                final top = det.box.top * scaleY;
                final right = det.box.right * scaleX;
                final bottom = det.box.bottom * scaleY;

                return Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: CustomPaint(
                    painter: _BoxPainter(
                      rect: Rect.fromLTRB(left, top, right, bottom),
                      label:
                          '$label ${(det.confidence * 100).toStringAsFixed(0)}%',
                      color: color,
                      canvasSize: Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                );
              },
            ),
          );
        }

        return Stack(children: boxes);
      },
    );
  }
}

// ─── Single-box painter ────────────────────────────────────────────────────

/// Paints one bounding box and its label badge.
class _BoxPainter extends CustomPainter {
  final Rect rect;
  final String label;
  final Color color;
  final Size canvasSize;

  const _BoxPainter({
    required this.rect,
    required this.label,
    required this.color,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Box fill
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..color = color.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill,
    );

    // Box border
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..color = color.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Label badge
    final textStyle = ui.TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.bold,
    );
    final pb =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(textAlign: TextAlign.left, maxLines: 1),
          )
          ..pushStyle(textStyle)
          ..addText(label);
    final paragraph = pb.build()
      ..layout(ui.ParagraphConstraints(width: canvasSize.width));

    final textWidth = min(paragraph.maxIntrinsicWidth + 12, canvasSize.width);
    final textHeight = paragraph.height + 6;
    final badgeLeft = rect.left;
    final badgeTop = max(0.0, rect.top - textHeight - 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(badgeLeft, badgeTop, textWidth, textHeight),
        const Radius.circular(4),
      ),
      Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill,
    );

    canvas.drawParagraph(paragraph, Offset(badgeLeft + 6, badgeTop + 3));
  }

  @override
  bool shouldRepaint(covariant _BoxPainter old) =>
      old.rect != rect || old.label != label || old.color != color;
}
