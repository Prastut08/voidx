// shell.dart — 5-tab navigation shell for CycloneX
import 'dart:async';
import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'services/websocket_service.dart';
import 'services/user_service.dart';
import 'services/location_service.dart';
import 'services/offline_sos_service.dart';
import 'Home.dart';
import 'Weather.dart';
import 'sos_chat_panel.dart';
import 'config/app_config.dart';

class AppShell extends StatefulWidget {
  const AppShell({Key? key}) : super(key: key);

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  StreamSubscription? _sosSub;
  StreamSubscription? _statusSub;
  bool _wsConnected = false;

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
      role: UserService.instance.userRole,
      lat: UserService.instance.lat,
      lng: UserService.instance.lng,
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
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: AppTheme.danger),
            SizedBox(width: 8),
            Text('CRITICAL SOS ALERT', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Category: ${sos['category'] ?? 'Emergency'}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Details: ${sos['description'] ?? 'Immediate assistance needed'}'),
            const SizedBox(height: 8),
            Text('Location: Lat ${sos['lat'] ?? 0}, Lng ${sos['lng'] ?? 0}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Dismiss', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _selectedIndex = 0); // View map
            },
            child: const Text('View on Map', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _handleStatusUpdate(Map<String, dynamic> data) {
    debugPrint("Status update received: $data");
  }

  @override
  void dispose() {
    _sosSub?.cancel();
    _statusSub?.cancel();
    WebSocketService.instance.disconnect();
    super.dispose();
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return Home();
      case 1:
        return WeatherScreen();
      case 2:
        return SOSChatPanel(
          currentLat: UserService.instance.lat,
          currentLng: UserService.instance.lng,
          backendUrl: AppConfig.baseUrl,
          onClose: () => setState(() => _selectedIndex = 0),
        );
      default:
        return Home();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _buildBody(),
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
            backgroundColor: Colors.white,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.cloud_outlined),
                selectedIcon: Icon(Icons.cloud),
                label: 'Weather',
              ),
              NavigationDestination(
                icon: Icon(Icons.emergency_outlined),
                selectedIcon: Icon(Icons.emergency),
                label: 'SOS Chat',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
