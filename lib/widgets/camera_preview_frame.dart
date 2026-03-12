import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../painters/grid_painter.dart';

class CameraPreviewFrame extends StatelessWidget {
  final CameraController? cameraController;

  const CameraPreviewFrame({
    super.key,
    required this.cameraController,
  });

  @override
  Widget build(BuildContext context) {
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double aspectRatio = cameraController!.value.aspectRatio;

        return AspectRatio(
          aspectRatio: 1 / aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16.0),
                child: CameraPreview(cameraController!),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(16.0),
                child: CustomPaint(
                  painter: GridPainter(),
                  child: Container(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
