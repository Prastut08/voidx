// shell.dart — 5-tab navigation shell
import 'dart:async';
import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'services/websocket_service.dart';
import 'services/user_service.dart';
import 'services/location_service.dart';
import 'services/offline_sos_service.dart';
import 'screens/monitoring_screen.dart';
import 'screens/sos_screen.dart';
import 'screens/rescue_network_screen.dart';
import 'screens/ai_assistant_screen.dart';
import 'screens/profile_screen.dart';
import 'widgets/sos_alert_overlay.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  StreamSubscription? _sosSub;
  StreamSubscription? _statusSub;
  bool _wsConnected = false;

  final _pages = const [
    MonitoringScreen(),
    SosScreen(),
    RescueNetworkScreen(),
    AiAssistantScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    await UserService.instance.load();

    // Get location then connect WS
    final pos = await LocationService.instance.getCurrentPosition();
    if (pos != null) {
      await UserService.instance.updateLocation(pos.latitude, pos.longitude);
    }

    WebSocketService.instance.connect(
      userId: UserService.instance.userId,
      role:   UserService.instance.userRole,
      lat:    UserService.instance.lat,
      lng:    UserService.instance.lng,
    );

    WebSocketService.instance.connectionState.listen((connected) {
      if (mounted) setState(() => _wsConnected = connected);
    });

    _sosSub = WebSocketService.instance.sosAlerts.listen(_showSosAlert);
    _statusSub = WebSocketService.instance.statusUpdates.listen(_handleStatusUpdate);

    // Sync any pending offline SOS
    OfflineSosService.instance.syncIfOnline();
  }

  void _showSosAlert(Map<String, dynamic> data) {
    final sos = data['sos'] as Map<String, dynamic>? ?? {};
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => SosAlertOverlay(
        sosData: sos,
        onAccept: () {
          Navigator.of(context).pop();
          setState(() => _selectedIndex = 2); // go to Rescue Network tab
        },
        onDismiss: () => Navigator.of(context).pop(),
      ),
    );
  }

  void _handleStatusUpdate(Map<String, dynamic> data) {
    // Bubble to rescue network screen via stream — no action needed here
  }

  @override
  void dispose() {
    _sosSub?.cancel();
    _statusSub?.cancel();
    WebSocketService.instance.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // WS status bar
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            height: _wsConnected ? 0 : 24,
            color: AppTheme.warning.withOpacity(0.9),
            alignment: Alignment.center,
            child: const Text(
              '⚡ Connecting to rescue network…',
              style: TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.w600),
            ),
          ),
          NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.radar_outlined),
                selectedIcon: Icon(Icons.radar),
                label: 'Monitoring',
              ),
              NavigationDestination(
                icon: Icon(Icons.emergency_outlined),
                selectedIcon: Icon(Icons.emergency),
                label: 'SOS',
              ),
              NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Rescue',
              ),
              NavigationDestination(
                icon: Icon(Icons.smart_toy_outlined),
                selectedIcon: Icon(Icons.smart_toy),
                label: 'AI Assistant',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
