import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/http_server.dart';
import 'detection_controller.dart';

class DetectionScreen extends ConsumerStatefulWidget {
  const DetectionScreen({super.key});

  @override
  ConsumerState<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends ConsumerState<DetectionScreen> {
  late HttpServerService _httpServer;

  @override
  void initState() {
    super.initState();
    // Start the server when the screen initializes
    _httpServer = HttpServerService(
      onDetectionReceived: (wasteType) {
        ref.read(detectionControllerProvider.notifier).handleNewDetection(wasteType);
      },
    );
    _httpServer.start();
  }

  @override
  Widget build(BuildContext context) {
    // Listen for state changes to show snackbar
    ref.listen(detectionControllerProvider, (previous, next) {
      next.when(
        data: (detection) {
          if (detection != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Successfully logged ${detection.wasteType} capture')),
            );
          }
        },
        error: (err, st) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to insert detection block.'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        },
        loading: () {},
      );
    });

    final state = ref.watch(detectionControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Waste Detection'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hub, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            const Text(
              'Listening for incoming OpenCV detections...',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'POST to http://127.0.0.1:8080/detect',
               style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            state.when(
              data: (detection) {
                if (detection == null) return const Text('No detections yet.');
                return Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text('Latest: ${detection.wasteType.toUpperCase()}', 
                          style: Theme.of(context).textTheme.titleLarge),
                        Text('Source: ${detection.locationSource}'),
                        Text('Coords: ${detection.latitude}, ${detection.longitude}'),
                        Text('Time: ${detection.detectedAt}'),
                      ],
                    ),
                  ),
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (e, st) => Text('Error: $e', style: const TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}
