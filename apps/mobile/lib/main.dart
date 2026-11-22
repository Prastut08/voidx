import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'getPhoneNumber.dart';
import 'getPermissions.dart';
import 'shell.dart';
import 'core/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  Widget _buildBody() {
    if (widget.phoneNumber == null) {
      return GetPhoneNumber();
    }
    if (!widget.permissionsGranted) {
      return GetPermissions();
    }
    return const AppShell();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CycloneX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: _buildBody(),
      ),
    );
  }
}
