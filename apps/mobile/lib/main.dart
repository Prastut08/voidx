// ============================================================
// CycloneX Android App — main.dart
// Entry point: initialises services, routes to shell
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'core/theme.dart';
import 'core/constants.dart';
import 'services/notification_service.dart';
import 'services/connectivity_service.dart';
import 'shell.dart';
import 'screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await NotificationService.instance.init();
  await ConnectivityService.instance.init();

  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString(AppConstants.prefUserId);

  runApp(CycloneXApp(isOnboarded: userId != null && userId.isNotEmpty));
}

class CycloneXApp extends StatelessWidget {
  final bool isOnboarded;
  const CycloneXApp({super.key, required this.isOnboarded});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CycloneX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: isOnboarded ? const AppShell() : const OnboardingScreen(),
    );
  }
}
