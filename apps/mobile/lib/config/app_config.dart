// lib/config/app_config.dart
import 'package:flutter/foundation.dart';

enum Environment { dev, prod }

class AppConfig {
  static Environment environment =
      kReleaseMode ? Environment.prod : Environment.dev;

  // Development URLs
  static const String _devBaseUrl = 'http://172.25.179.252:8080';
  static const String _devWsUrl = 'ws://172.25.179.252:8080';

  // Production URLs
  static const String _prodBaseUrl = 'https://api.cyclonex.live';
  static const String _prodWsUrl = 'wss://api.cyclonex.live';

  /// Centralized Backend Base URL
  static String get baseUrl {
    const fromDefine = String.fromEnvironment('BACKEND_URL');
    if (fromDefine.isNotEmpty) return fromDefine;
    return environment == Environment.prod ? _prodBaseUrl : _devBaseUrl;
  }

  /// Centralized WebSocket Base URL
  static String get wsUrl {
    const fromDefine = String.fromEnvironment('WS_URL');
    if (fromDefine.isNotEmpty) return fromDefine;
    return environment == Environment.prod ? _prodWsUrl : _devWsUrl;
  }

  /// API Route Definitions (matching backend exactly)
  static const String apiSosCreate = '/api/sos/create';
  static const String apiSosList = '/api/sos/list';
  static const String apiSosAccept = '/api/sos/{id}/accept';
  static const String apiSosStatus = '/api/sos/{id}/status';
  static const String apiRescueTeams = '/api/rescue/teams';
  static const String apiRescueNearby = '/api/rescue/nearby';
  static const String apiChatEmergency = '/api/chat/emergency';
  static const String apiCyclonesActive = '/api/cyclones/active';
  static const String apiCyclonesHealth = '/api/cyclones/health';
  static const String apiOfflineRelay = '/api/offline/relay';
  static const String apiOfflineSync = '/api/offline/sync';
  static const String wsRescue = '/ws/rescue';

  /// Health endpoint URL
  static String get healthUrl => '$baseUrl$apiCyclonesHealth';
}
