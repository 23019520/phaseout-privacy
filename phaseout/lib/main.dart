// ─────────────────────────────────────────────────────────────
//  lib/main.dart
//  PhaseOut — App entry point (Sprint 4 final)
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_options.dart';
import 'app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'main_navigator_key.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase — must be first
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 2. Crashlytics — catch all Flutter errors
  FlutterError.onError =
      FirebaseCrashlytics.instance.recordFlutterFatalError;

  // 3. Notifications — channels before BGS
  await NotificationService.initialise();

  // 4. Background service
  await BackgroundService.initialise();

  runApp(const PhaseOutApp());
}

class PhaseOutApp extends StatelessWidget {
  const PhaseOutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                      'PhaseOut',
      debugShowCheckedModeBanner: false,
      theme:                      AppTheme.light,
      darkTheme:                  AppTheme.dark,
      themeMode:                  ThemeMode.dark,
      navigatorKey:               appNavigatorKey,
      home:                       const SplashScreen(),
    );
  }
}