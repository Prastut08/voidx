// core/constants.dart
import '../config/app_config.dart';

class AppConstants {
  // Backend & WebSocket URLs dynamically resolved from centralized AppConfig
  static String get backendBase => AppConfig.baseUrl;
  static String get wsBase      => AppConfig.wsUrl;

  // API routes (match fastapi_server.py exactly)
  static const String apiSosCreate      = AppConfig.apiSosCreate;
  static const String apiSosList        = AppConfig.apiSosList;
  static const String apiSosAccept      = AppConfig.apiSosAccept;
  static const String apiSosStatus      = AppConfig.apiSosStatus;
  static const String apiRescueTeams    = AppConfig.apiRescueTeams;
  static const String apiRescueNearby   = AppConfig.apiRescueNearby;
  static const String apiChatEmergency  = AppConfig.apiChatEmergency;
  static const String apiCyclonesActive = AppConfig.apiCyclonesActive;
  static const String apiCyclonesHealth = AppConfig.apiCyclonesHealth;
  static const String apiOfflineRelay   = AppConfig.apiOfflineRelay;
  static const String apiOfflineSync    = AppConfig.apiOfflineSync;
  static const String wsRescue          = AppConfig.wsRescue;

  // SharedPrefs keys
  static const String prefUserId    = 'userId';
  static const String prefUserName  = 'userName';
  static const String prefUserRole  = 'userRole';
  static const String prefUserLat   = 'userLat';
  static const String prefUserLng   = 'userLng';
  static const String prefPendingSOS = 'pendingSosQueue';

  // Roles
  static const String roleUser        = 'USER';
  static const String roleVolunteer   = 'VOLUNTEER';
  static const String roleRescueTeam  = 'RESCUE_TEAM';
  static const String roleCoordinator = 'COORDINATOR';
}
