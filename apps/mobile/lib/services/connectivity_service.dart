// services/connectivity_service.dart
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final ConnectivityService instance = ConnectivityService._();
  ConnectivityService._();

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  Future<void> init() async {
    final result = await Connectivity().checkConnectivity();
    _isOnline = result != ConnectivityResult.none;
    Connectivity().onConnectivityChanged.listen((r) {
      _isOnline = r != ConnectivityResult.none;
    });
  }
}
