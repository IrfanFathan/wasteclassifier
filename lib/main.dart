import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF9FAFB),
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: Color(0xFF14171A),
          onPrimary: Colors.white,
          secondary: Color(0xFF6B7280),
          onSecondary: Colors.white,
          error: Color(0xFFC62828),
          onError: Colors.white,
          surface: Colors.white,
          onSurface: Color(0xFF14171A),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Color(0xFFF9FAFB),
          foregroundColor: Color(0xFF14171A),
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          color: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF14171A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 20,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFD1D5DB),
          thickness: 0.5,
        ),
        textTheme: GoogleFonts.interTextTheme(
          const TextTheme(
            displayLarge: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w600,
              color: Color(0xFF14171A),
            ),
            headlineMedium: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Color(0xFF14171A),
            ),
            titleMedium: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF14171A),
            ),
            bodyLarge: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: Color(0xFF14171A),
              height: 1.5,
            ),
            bodyMedium: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Color(0xFF6B7280),
              height: 1.5,
            ),
            labelSmall: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Color(0xFFD1D5DB),
            ),
          ),
        ),
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
