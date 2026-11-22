// core/constants.dart
class AppConstants {
  // Backend — change to your server IP for device testing
  static const String backendBase = 'http://172.25.179.252:8080';
  static const String wsBase      = 'ws://172.25.179.252:8080';

  // API routes (match fastapi_server.py exactly)
  static const String apiSosCreate      = '/api/sos/create';
  static const String apiSosList        = '/api/sos/list';
  static const String apiSosAccept      = '/api/sos/{id}/accept';
  static const String apiSosStatus      = '/api/sos/{id}/status';
  static const String apiRescueTeams    = '/api/rescue/teams';
  static const String apiRescueNearby   = '/api/rescue/nearby';
  static const String apiChatEmergency  = '/api/chat/emergency';
  static const String apiCyclonesActive = '/api/cyclones/active';
  static const String apiCyclonesHealth = '/api/cyclones/health';
  static const String apiOfflineSync    = '/api/offline/sync';
  static const String wsRescue          = '/ws/rescue';

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
