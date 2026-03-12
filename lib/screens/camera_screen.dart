import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../theme/app_theme.dart';
import '../widgets/top_bar.dart';
import '../widgets/camera_preview_frame.dart';
import '../widgets/bottom_info_sheet.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _error = 'No cameras found';
        });
        return;
      }

      await _startCamera(_selectedCameraIndex);
    } catch (e) {
      setState(() {
        _error = 'Error initializing camera: $e';
      });
    }
  }

  Future<void> _startCamera(int cameraIndex) async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
    }

    final camera = _cameras[cameraIndex];
    _cameraController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _selectedCameraIndex = cameraIndex;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error starting camera: $e';
        });
      }
    }
  }

  void _switchCamera() {
    if (_cameras.length < 2) return;
    final newIndex = (_selectedCameraIndex + 1) % _cameras.length;
    _startCamera(newIndex);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar Zone (Fixed 60px height within widget)
            TopBar(
              onBinSetupPressed: () {
                // If navigation is needed, do it here
              },
              onSwitchCameraPressed: _switchCamera,
            ),
            
            // Camera + Grid Frame Zone (Expanded)
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : CameraPreviewFrame(cameraController: _cameraController),
            ),
            
            // Bottom Sheet Zone
            const BottomInfoSheet(),
          ],
        ),
      ),
    );
  }
}
