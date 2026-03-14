import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/upload_screen.dart';
import 'screens/bin_setup_screen.dart';
import 'screens/detection_screen.dart';
import 'screens/connection_screen.dart';
import 'utils/config_manager.dart';
import 'utils/model_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WasteClassifierApp());
}

class WasteClassifierApp extends StatelessWidget {
  const WasteClassifierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waste Classifier',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF00B0FF),
        ),
      ),
      home: const ConnectionScreen(),
      routes: {
        '/upload': (context) => const UploadScreen(),
        '/detect': (context) => const DetectionScreen(),
      },
    );
  }
}

class _AppStartup extends StatefulWidget {
  const _AppStartup();

  @override
  State<_AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<_AppStartup> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    // Check model loaded flag
    final modelLoaded = await ConfigManager.isModelLoaded();
    if (!modelLoaded) {
      // Double-check actual files
      final filesExist = await ModelManager.modelFilesExist();
      if (!filesExist) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const UploadScreen()),
        );
        return;
      }
    }

    // Model exists — load labels and config
    final labels = await ConfigManager.loadLabels();
    final config = await ConfigManager.loadConfig();

    if (!mounted) return;

    if (config == null || config.bins.isEmpty) {
      // Labels exist but no config — go to setup
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BinSetupScreen(labels: labels),
        ),
      );
    } else {
      // Fully configured — go to detection
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DetectionScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '♻️',
              style: TextStyle(fontSize: 64),
            ),
            const SizedBox(height: 24),
            Text(
              'Waste Classifier',
              style: GoogleFonts.inter(
                color: const Color(0xFF14171A),
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: Color(0xFF14171A)),
          ],
        ),
      ),
    );
  }
}
