import 'package:flutter/material.dart';
import 'screens/upload_screen.dart';
import 'screens/bin_setup_screen.dart';
import 'screens/detection_screen.dart';
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
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        colorScheme: ColorScheme.dark(
          primary: Colors.greenAccent,
          secondary: Colors.greenAccent,
          surface: const Color(0xFF16213E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF16213E),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: Colors.greenAccent,
          thumbColor: Colors.greenAccent,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white),
          bodyLarge: TextStyle(color: Colors.white),
        ),
        useMaterial3: true,
      ),
      home: const _AppStartup(),
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
    return const Scaffold(
      backgroundColor: Color(0xFF1A1A2E),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '♻️',
              style: TextStyle(fontSize: 64),
            ),
            SizedBox(height: 24),
            Text(
              'Waste Classifier',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 32),
            CircularProgressIndicator(color: Colors.greenAccent),
          ],
        ),
      ),
    );
  }
}
