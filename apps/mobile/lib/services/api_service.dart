// services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  String get _baseUrl => AppConfig.baseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  // ── SOS ──────────────────────────────────────────────────
  Future<Map<String, dynamic>> createSos(Map<String, dynamic> payload) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl${AppConfig.apiSosCreate}'),
          headers: _headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 10));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getSosList() async {
    final res = await http
        .get(Uri.parse('$_baseUrl${AppConfig.apiSosList}'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> acceptSos(
      String sosId, String responderId, String responderName) async {
    final url = '$_baseUrl/api/sos/$sosId/accept';
    final res = await http
        .post(
          Uri.parse(url),
          headers: _headers,
          body: jsonEncode({
            'responder_id': responderId,
            'responder_name': responderName,
          }),
        )
        .timeout(const Duration(seconds: 10));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateSosStatus(
      String sosId, String status, String responderId,
      {String? note}) async {
    final url = '$_baseUrl/api/sos/$sosId/status';
    final res = await http
        .post(
          Uri.parse(url),
          headers: _headers,
          body: jsonEncode({
            'status': status,
            'responder_id': responderId,
            if (note != null) 'note': note,
          }),
        )
        .timeout(const Duration(seconds: 10));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Rescue Teams ─────────────────────────────────────────
  Future<Map<String, dynamic>> getRescueTeams() async {
    final res = await http
        .get(Uri.parse('$_baseUrl${AppConfig.apiRescueTeams}'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getNearbyTeams(
      double lat, double lng, String? category,
      {int limit = 5}) async {
    final uri = Uri.parse('$_baseUrl${AppConfig.apiRescueNearby}').replace(
      queryParameters: {
        'lat': lat.toString(),
        'lng': lng.toString(),
        if (category != null) 'category': category,
        'limit': limit.toString(),
      },
    );
    final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Chat / RAG ───────────────────────────────────────────
  Future<Map<String, dynamic>> queryChatEmergency(String query,
      {String? category}) async {
    final uri = Uri.parse('$_baseUrl${AppConfig.apiChatEmergency}').replace(
      queryParameters: {
        'query': query,
        if (category != null) 'category': category,
      },
    );
    final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Cyclones ─────────────────────────────────────────────
  Future<Map<String, dynamic>> getActiveCyclones() async {
    final res = await http
        .get(Uri.parse('$_baseUrl${AppConfig.apiCyclonesActive}'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getCyclonesHealth() async {
    final res = await http
        .get(Uri.parse('$_baseUrl${AppConfig.apiCyclonesHealth}'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Offline Sync ─────────────────────────────────────────
  Future<Map<String, dynamic>> syncOfflineSos(
      List<Map<String, dynamic>> messages) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl${AppConfig.apiOfflineSync}'),
          headers: _headers,
          body: jsonEncode({'messages': messages}),
        )
        .timeout(const Duration(seconds: 10));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}

