// services/connectivity_service.dart
import 'dart:async';
import 'package:internet_connection_checker/internet_connection_checker.dart';

class ConnectivityService {
  static final ConnectivityService instance = ConnectivityService._();
  ConnectivityService._();

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  Stream<bool> get onConnectivityChanged => _controller.stream;

  Future<void> init() async {
    _isOnline = await InternetConnectionChecker().hasConnection;
    InternetConnectionChecker().onStatusChange.listen((status) {
      _isOnline = status == InternetConnectionStatus.connected;
      _controller.add(_isOnline);
    });
  }
}
