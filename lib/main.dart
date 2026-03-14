import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'core/background_service.dart';
import 'core/supabase_client.dart';
import 'features/device/device_repository.dart';
import 'features/location/background_task.dart';
import 'screens/connection_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load environment variables from the bundled .env asset.
  await dotenv.load(fileName: '.env');

  // 2. Initialize Supabase using values from .env.
  await SupabaseService.initialize();

  // 3. Configure the foreground task (must happen before startService).
  WastoForegroundService.init();

  // 4. Register the workmanager callback dispatcher for the background fallback.
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  // 5. Register/fetch this device and start background location tracking.
  try {
    final deviceId = await DeviceRepository.registerOrFetchDeviceId();

    // Start the foreground service for the strict 2-min ping cadence.
    await WastoForegroundService.start();

    // Register the workmanager periodic task as a 15-min OS-floor fallback.
    await registerWorkmanagerTask(deviceId);
  } catch (e) {
    debugPrint('main: startup error: $e');
  }

  runApp(const ProviderScope(child: WasteClassifierApp()));
}

class WasteClassifierApp extends StatelessWidget {
  const WasteClassifierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        title: 'WASTO Tracker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Colors.black,
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00E676),
            secondary: Color(0xFF00B0FF),
          ),
        ),
        home: const ConnectionScreen(),
      ),
    );
  }
}
