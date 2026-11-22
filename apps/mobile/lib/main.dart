import 'package:flutter/material.dart';

import 'package:flutter_config/flutter_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'getPhoneNumber.dart';
import 'getPermissions.dart';
import 'Home.dart';
import 'Weather.dart';

class CustomNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemTapped;

  CustomNavigationBar({
    Key? key,
    required this.selectedIndex,
    required this.onItemTapped,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onItemTapped,
      backgroundColor: Colors.white,
      destinations: [
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
        //<------------------ADD MORE OPTIONS AS NEEDED----------------->
      ],
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await FlutterConfig.loadEnvVariables();
  } catch (e) {
    debugPrint("FlutterConfig not supported on this platform: $e");
  }
  final prefs = await SharedPreferences.getInstance();
  var phoneNumber = prefs.getString('phoneNumber');
  bool permissionsGranted = prefs.getBool('permissionsGranted') ?? false;

  runApp(
      MyApp(phoneNumber: phoneNumber, permissionsGranted: permissionsGranted));
}

class MyApp extends StatefulWidget {
  final String? phoneNumber;
  final bool permissionsGranted;

  MyApp({Key? key, required this.phoneNumber, required this.permissionsGranted})
      : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  int _selectedIndex = 0;

  Widget _buildBody() {
    if (widget.phoneNumber == null) {
      return GetPhoneNumber();
    }
    if (!widget.permissionsGranted) {
      return GetPermissions();
    }
    return _selectedIndex == 0 ? Home() : WeatherScreen();
  }

  @override
  Widget build(BuildContext context) {
    final bool isSetupComplete =
        widget.phoneNumber != null && widget.permissionsGranted;

    return MaterialApp(
      title: 'Sahaya',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: _buildBody(),
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }
}
