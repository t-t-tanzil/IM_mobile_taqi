import 'package:flutter/material.dart';

import 'core/di/service_locator.dart';
import 'presentation/splash/splash_screen.dart';
import 'presentation/theme/app_theme.dart';
import 'services/background_sync/background_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupServiceLocator();
  // Single clear init path for the background-work callback registration -
  // must happen once at startup, before anything schedules work.
  await getIt<BackgroundSyncService>().initialize();
  runApp(const CameraSyncApp());
}

class CameraSyncApp extends StatelessWidget {
  const CameraSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Camera Sync',
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      home: const SplashScreen(),
    );
  }
}
