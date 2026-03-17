import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/detection.dart';
import '../utils/detection_constants.dart';

// ─── Color palette ─────────────────────────────────────────────────────────

const _colors = [
  Color(0xFF00E676), // green
  Color(0xFF00B0FF), // cyan
  Color(0xFFFF5252), // red
  Color(0xFFFFD740), // amber
  Color(0xFFE040FB), // purple
  Color(0xFF18FFFF), // teal
  Color(0xFF69F0AE), // light green
  Color(0xFF40C4FF), // light blue
  Color(0xFFFF4081), // pink
  Color(0xFFFF6E40), // deep orange
];

Color _colorForLabel(String label, Map<String, int> indexMap) {
  if (!indexMap.containsKey(label)) {
    indexMap[label] = indexMap.length;
  }
  return _colors[indexMap[label]! % _colors.length];
}

// ─── Tracked detection entry ────────────────────────────────────────────────

/// A single classification result being tracked with its animation controller.
class _TrackedDetection {
  Detection det;
  final AnimationController ctrl;
  bool leaving = false;

  _TrackedDetection({required this.det, required this.ctrl});
}

// ─── Public widget ─────────────────────────────────────────────────────────

/// Overlay that renders an animated classification label banner for the
/// Teachable Machine classification result.
///
/// Since TM classifies the entire frame (no bounding boxes), this overlay
/// shows a single top-center label badge instead of per-object boxes.
///
/// Each classification result fades **in** over 150 ms and **out** over 300 ms.
/// Label changes are tracked by IoU matching (full-frame boxes always match
/// with IoU = 1.0 when the label is the same, so transitions between
/// different labels get the fade-out/fade-in treatment).
class DetectionOverlay extends StatefulWidget {
  /// Current detections to render (0 or 1 items for classification).
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
  State<DetectionOverlay> createState() => _DetectionOverlayState();
}

// ─── State ──────────────────────────────────────────────────────────────────

class _DetectionOverlayState extends State<DetectionOverlay>
    with TickerProviderStateMixin {
  /// All currently tracked detections (including those fading out).
  final List<_TrackedDetection> _tracked = [];

  /// Stable label -> color index mapping so colors don't jump.
  final Map<String, int> _colorIndex = {};

  @override
  void didUpdateWidget(DetectionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reconcile(widget.detections);
  }

  /// Match incoming detections to existing tracked entries by IoU + label,
  /// start fade-ins for new arrivals, and fade-out departures.
  void _reconcile(List<Detection> incoming) {
    final matched = List<bool>.filled(_tracked.length, false);
    final incomingMatched = List<bool>.filled(incoming.length, false);

    // Match incoming to tracked by same label + IoU >= threshold.
    for (int i = 0; i < incoming.length; i++) {
      final det = incoming[i];
      double bestIou = kSmootherMatchIou; // minimum threshold
      int bestIdx = -1;

      for (int j = 0; j < _tracked.length; j++) {
        if (matched[j]) continue;
        if (_tracked[j].det.label != det.label) continue;
        final iou = _iou(_tracked[j].det.box, det.box);
        if (iou >= bestIou) {
          bestIou = iou;
          bestIdx = j;
        }
      }

      if (bestIdx >= 0) {
        // Update the existing entry with the fresh detection.
        matched[bestIdx] = true;
        incomingMatched[i] = true;
        _tracked[bestIdx].det = det;
        _tracked[bestIdx].leaving = false;
        final ctrl = _tracked[bestIdx].ctrl;
        if (!ctrl.isAnimating && ctrl.value < 1.0) ctrl.forward();
      }
    }

    // Unmatched tracked -> start fade-out.
    for (int j = 0; j < _tracked.length; j++) {
      if (!matched[j] && !_tracked[j].leaving) {
        _tracked[j].leaving = true;
        final ctrl = _tracked[j].ctrl;
        if (!ctrl.isAnimating && ctrl.value > 0.0) {
          ctrl.reverse().then((_) {
            if (mounted) {
              setState(
                () => _tracked.removeWhere(
                  (t) => t.leaving && t.ctrl.value == 0.0,
                ),
              );
            }
          });
        }
      }
    }

    // Unmatched incoming -> create new tracked entry and fade in.
    for (int i = 0; i < incoming.length; i++) {
      if (incomingMatched[i]) continue;
      final det = incoming[i];
      _colorForLabel(det.label, _colorIndex); // register color slot
      final ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 150),
        reverseDuration: const Duration(milliseconds: 300),
      );
      _tracked.add(_TrackedDetection(det: det, ctrl: ctrl));
      ctrl.forward();
    }
  }

  @override
  void dispose() {
    for (final t in _tracked) {
      t.ctrl.dispose();
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
        return Stack(
          children: _tracked.map((t) {
            final color = _colorForLabel(t.det.label, _colorIndex);
            return AnimatedBuilder(
              animation: t.ctrl,
              builder: (context, _) {
                final opacity = t.ctrl.value;
                if (opacity <= 0) return const SizedBox.shrink();

                return CustomPaint(
                  painter: _ClassificationPainter(
                    label:
                        '${t.det.label}  ${(t.det.confidence * 100).toStringAsFixed(0)}%',
                    color: color,
                    opacity: opacity.clamp(0.0, 1.0),
                    canvasSize: Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    ),
                  ),
                  child: const SizedBox.expand(),
                );
              },
            );
          }).toList(),
        );
      },
    );
  }
}

// ─── IoU helper ────────────────────────────────────────────────────────────

double _iou(Rect a, Rect b) {
  final il = a.left > b.left ? a.left : b.left;
  final it = a.top > b.top ? a.top : b.top;
  final ir = a.right < b.right ? a.right : b.right;
  final ib = a.bottom < b.bottom ? a.bottom : b.bottom;
  if (ir <= il || ib <= it) return 0.0;
  final inter = (ir - il) * (ib - it);
  return inter / (a.width * a.height + b.width * b.height - inter);
}

// ─── Classification label painter ──────────────────────────────────────────

/// Paints a classification label banner at the top-center of the overlay.
///
/// Instead of bounding boxes (which are meaningless for whole-frame
/// classification), this draws a prominent label badge with a subtle
/// full-frame border tint.
class _ClassificationPainter extends CustomPainter {
  final String label;
  final Color color;
  final double opacity;
  final Size canvasSize;

  const _ClassificationPainter({
    required this.label,
    required this.color,
    required this.opacity,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── 1. Subtle full-frame border tint ──────────────────────────────────
    final frameRect = Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frameRect, const Radius.circular(4)),
      Paint()
        ..color = color.withValues(alpha: 0.06 * opacity)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(frameRect.deflate(1.5), const Radius.circular(4)),
      Paint()
        ..color = color.withValues(alpha: 0.35 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    );

    // ── 2. Label badge at top-center ──────────────────────────────────────
    final textStyle = ui.TextStyle(
      color: Colors.white.withValues(alpha: opacity),
      fontSize: 16,
      fontWeight: FontWeight.bold,
    );
    final pb =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(textAlign: TextAlign.center, maxLines: 1),
          )
          ..pushStyle(textStyle)
          ..addText(label);
    final paragraph = pb.build()
      ..layout(ui.ParagraphConstraints(width: canvasSize.width));

    final textWidth = paragraph.maxIntrinsicWidth + 28;
    final textHeight = paragraph.height + 14;
    final badgeLeft = (canvasSize.width - textWidth) / 2;
    const badgeTop = 16.0;

    // Badge background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(badgeLeft, badgeTop, textWidth, textHeight),
        const Radius.circular(10),
      ),
      Paint()
        ..color = color.withValues(alpha: 0.85 * opacity)
        ..style = PaintingStyle.fill,
    );

    // Badge text
    canvas.drawParagraph(paragraph, Offset(badgeLeft + 14, badgeTop + 7));
  }

  @override
  bool shouldRepaint(covariant _ClassificationPainter old) =>
      old.label != label || old.color != color || old.opacity != opacity;
}
