import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../painters/grid_painter.dart';
import 'axis_labels.dart';

class CameraPreviewFrame extends StatelessWidget {
  final CameraController? cameraController;

  const CameraPreviewFrame({
    super.key,
    required this.cameraController,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Ruler reserved spaces
        const double leftRulerWidth = 24.0;
        const double rightRulerWidth = 24.0;
        const double topRulerHeight = 20.0;
        
        // Calculate the camera preview dimensions
        final double cameraWidth = constraints.maxWidth - leftRulerWidth - rightRulerWidth;
        final double cameraHeight = constraints.maxHeight - topRulerHeight;
        
        // Logical grid dimensions based on Y: -2 to 2 (4 cells), X: -4 to 4 (8 cells)
        final double cellWidth = cameraWidth / 8;
        final double cellHeight = cameraHeight / 4;

        return Row(
          children: [
            // Left Ruler Column
            Padding(
              padding: const EdgeInsets.only(top: topRulerHeight),
              child: YAxisLabels(
                cellHeight: cellHeight,
                right: false,
              ),
            ),
            
            // Middle section (Top Ruler + Camera)
            Expanded(
              child: Column(
                children: [
                  // Top Ruler Row
                  XAxisLabels(cellWidth: cellWidth),
                  
                  // Camera Preview Region
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: Colors.black, // Background while loading
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Actively display camera feed
                          if (cameraController != null && cameraController!.value.isInitialized)
                            Transform.scale(
                              scale: _calculateCameraScale(cameraWidth, cameraHeight, cameraController!),
                              child: Center(
                                child: CameraPreview(cameraController!),
                              ),
                            )
                          else
                            const Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                          
                          // Grid Overlay
                          CustomPaint(
                            painter: GridPainter(),
                            child: Container(), // Fills the stack space
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Right Ruler Column
            Padding(
              padding: const EdgeInsets.only(top: topRulerHeight),
              child: YAxisLabels(
                cellHeight: cellHeight,
                right: true,
              ),
            ),
          ],
        );
      },
    );
  }

  double _calculateCameraScale(double widgetWidth, double widgetHeight, CameraController controller) {
    // Camera previews often need to be scaled correctly to fill the area without distortion.
    if (!controller.value.isInitialized) return 1.0;
    
    // Size of the area we are rendering to
    final Size widgetSize = Size(widgetWidth, widgetHeight);
    
    // Aspect ratio of the area
    final double widgetAspectRatio = widgetSize.width / widgetSize.height;
    
    // Aspect ratio of the camera (note: camera is often landscape in its native orientation, 
    // so we use aspect ratio depending on whether it's portrait or landscape)
    final double cameraAspectRatio = controller.value.aspectRatio;
    
    // In portrait mode, aspect ratio is inverted
    final double adjustedCameraAspectRatio = 1 / cameraAspectRatio;
    
    if (widgetAspectRatio > adjustedCameraAspectRatio) {
      // Widget is wider than camera's aspect ratio
      return widgetAspectRatio / adjustedCameraAspectRatio;
    } else {
      // Widget is taller than camera's aspect ratio
      return adjustedCameraAspectRatio / widgetAspectRatio;
    }
  }
}
