// services/user_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';

class UserService {
  static final UserService instance = UserService._();
  UserService._();

  String _userId = '';
  String _userName = '';
  String _userRole = AppConstants.roleUser;
  double _lat = 20.5937;
  double _lng = 78.9629;

  String get userId   => _userId;
  String get userName => _userName;
  String get userRole => _userRole;
  double get lat      => _lat;
  double get lng      => _lng;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _userId   = p.getString(AppConstants.prefUserId)   ?? '';
    _userName = p.getString(AppConstants.prefUserName) ?? 'CycloneX User';
    _userRole = p.getString(AppConstants.prefUserRole) ?? AppConstants.roleUser;
    _lat      = p.getDouble(AppConstants.prefUserLat)  ?? 20.5937;
    _lng      = p.getDouble(AppConstants.prefUserLng)  ?? 78.9629;
  }

  Future<void> register(String name, String role) async {
    final p = await SharedPreferences.getInstance();
    _userId   = const Uuid().v4();
    _userName = name;
    _userRole = role;
    await p.setString(AppConstants.prefUserId,   _userId);
    await p.setString(AppConstants.prefUserName, _userName);
    await p.setString(AppConstants.prefUserRole, _userRole);
  }

  Future<void> updateLocation(double lat, double lng) async {
    _lat = lat;
    _lng = lng;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(AppConstants.prefUserLat, lat);
    await p.setDouble(AppConstants.prefUserLng, lng);
  }
}
