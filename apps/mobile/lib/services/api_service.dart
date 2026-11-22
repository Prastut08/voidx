// services/api_service.dart
import 'package:dio/dio.dart';
import '../core/constants.dart';

class ApiService {
  static final ApiService instance = ApiService._();
  late final Dio _dio;

  ApiService._() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.backendBase,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(LogInterceptor(responseBody: false, requestBody: false));
  }

  // ── SOS ──────────────────────────────────────────────────
  Future<Map<String, dynamic>> createSos(Map<String, dynamic> payload) async {
    final r = await _dio.post(AppConstants.apiSosCreate, data: payload);
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getSosList() async {
    final r = await _dio.get(AppConstants.apiSosList);
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> acceptSos(
      String sosId, String responderId, String responderName) async {
    final url = '/api/sos/$sosId/accept';
    final r = await _dio.post(url, data: {
      'responder_id': responderId,
      'responder_name': responderName,
    });
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateSosStatus(
      String sosId, String status, String responderId,
      {String? note}) async {
    final url = '/api/sos/$sosId/status';
    final r = await _dio.post(url, data: {
      'status': status,
      'responder_id': responderId,
      if (note != null) 'note': note,
    });
    return r.data as Map<String, dynamic>;
  }

  // ── Rescue Teams ─────────────────────────────────────────
  Future<Map<String, dynamic>> getRescueTeams() async {
    final r = await _dio.get(AppConstants.apiRescueTeams);
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getNearbyTeams(
      double lat, double lng, String? category, {int limit = 5}) async {
    final r = await _dio.get(AppConstants.apiRescueNearby, queryParameters: {
      'lat': lat,
      'lng': lng,
      if (category != null) 'category': category,
      'limit': limit,
    });
    return r.data as Map<String, dynamic>;
  }

  // ── Chat / RAG ───────────────────────────────────────────
  Future<Map<String, dynamic>> queryChatEmergency(String query,
      {String? category}) async {
    final r = await _dio.get(AppConstants.apiChatEmergency, queryParameters: {
      'query': query,
      if (category != null) 'category': category,
    });
    return r.data as Map<String, dynamic>;
  }

  // ── Cyclones ─────────────────────────────────────────────
  Future<Map<String, dynamic>> getActiveCyclones() async {
    final r = await _dio.get(AppConstants.apiCyclonesActive);
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getCyclonesHealth() async {
    final r = await _dio.get(AppConstants.apiCyclonesHealth);
    return r.data as Map<String, dynamic>;
  }

  // ── Offline Sync ─────────────────────────────────────────
  Future<Map<String, dynamic>> syncOfflineSos(
      List<Map<String, dynamic>> messages) async {
    final r = await _dio
        .post(AppConstants.apiOfflineSync, data: {'messages': messages});
    return r.data as Map<String, dynamic>;
  }
}
