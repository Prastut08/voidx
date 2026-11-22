// services/offline_sos_service.dart
// Persists pending SOS requests when offline and syncs when connectivity returns
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../models/models.dart';
import 'api_service.dart';
import 'connectivity_service.dart';

class OfflineSosService {
  static final OfflineSosService instance = OfflineSosService._();
  OfflineSosService._();

  Future<void> queue(SosRequest sos) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(AppConstants.prefPendingSOS) ?? [];
    raw.add(jsonEncode(sos.toJson()));
    await prefs.setStringList(AppConstants.prefPendingSOS, raw);
  }

  Future<List<SosRequest>> getPending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(AppConstants.prefPendingSOS) ?? [];
    return raw.map((s) => SosRequest.fromJson(jsonDecode(s))).toList();
  }

  Future<int> syncIfOnline() async {
    if (!ConnectivityService.instance.isOnline) return 0;
    final pending = await getPending();
    if (pending.isEmpty) return 0;

    try {
      final result = await ApiService.instance
          .syncOfflineSos(pending.map((s) => s.toJson()).toList());
      final synced = result['synced_count'] ?? 0;
      if (synced > 0) await _clearSynced(synced, pending);
      return synced;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _clearSynced(int count, List<SosRequest> all) async {
    final prefs = await SharedPreferences.getInstance();
    // Remove the first `count` entries that were synced
    final remaining = all.skip(count).map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(AppConstants.prefPendingSOS, remaining);
  }
}
