import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Offline-First Emergency Communication Service.
/// Supports Local Persistent Queuing, Store-Carry-Forward D2D Relay,
/// and Eventual Backend Synchronization when connectivity is restored.
class EmergencyRelayService {
  static const MethodChannel _platformChannel =
      MethodChannel('com.example.cyclonex/offline_relay');

  static const String _storageKey = 'cyclonex_pending_emergency_messages';

  static final EmergencyRelayService _instance =
      EmergencyRelayService._internal();
  factory EmergencyRelayService() => _instance;
  EmergencyRelayService._internal() {
    _initPlatformCallbacks();
  }

  final StreamController<int> _peerCountController =
      StreamController<int>.broadcast();
  Stream<int> get peerCountStream => _peerCountController.stream;

  int _discoveredPeers = 0;
  int get discoveredPeers => _discoveredPeers;

  bool _isSimulationMode = false;
  bool get isSimulationMode => _isSimulationMode;
  set isSimulationMode(bool val) => _isSimulationMode = val;

  void _initPlatformCallbacks() {
    if (!kIsWeb) {
      _platformChannel.setMethodCallHandler((call) async {
        if (call.method == 'onRelayPeerFound') {
          final count = (call.arguments['peerCount'] as num?)?.toInt() ?? 1;
          _discoveredPeers = count;
          _peerCountController.add(_discoveredPeers);
        }
      });
    }
  }

  /// Store an SOS emergency request locally with guaranteed persistence
  Future<void> persistEmergencyMessage(Map<String, dynamic> message) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> queued = prefs.getStringList(_storageKey) ?? [];

    // Deduplication check
    final id = message['sos_id'];
    queued.removeWhere((item) {
      try {
        final decoded = json.decode(item);
        return decoded['sos_id'] == id;
      } catch (_) {
        return false;
      }
    });

    queued.add(json.encode(message));
    await prefs.setStringList(_storageKey, queued);

    // Queue in native Android BLE store if supported
    if (!kIsWeb) {
      try {
        await _platformChannel.invokeMethod('queueEmergencyMessage', {
          'message': json.encode(message),
        });
      } catch (e) {
        debugPrint('Native relay queue note: $e');
      }
    }
  }

  /// Retrieve all locally queued emergency messages
  Future<List<Map<String, dynamic>>> getQueuedMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> queued = prefs.getStringList(_storageKey) ?? [];
    final List<Map<String, dynamic>> result = [];

    for (final raw in queued) {
      try {
        result.add(Map<String, dynamic>.from(json.decode(raw)));
      } catch (_) {}
    }
    return result;
  }

  /// Start device-to-device offline emergency advertising/scanning
  Future<bool> startOfflineRelay() async {
    if (kIsWeb || _isSimulationMode) {
      // In Web / Demo environment, provide a realistic hardware simulation timer
      _startSimulatedRelayDiscovery();
      return true;
    }

    try {
      final success = await _platformChannel.invokeMethod<bool>('startRelay');
      return success ?? false;
    } catch (e) {
      debugPrint('Start BLE Relay fallback to simulation: $e');
      _startSimulatedRelayDiscovery();
      return false;
    }
  }

  void _startSimulatedRelayDiscovery() {
    Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_discoveredPeers < 3) {
        _discoveredPeers += 1;
        _peerCountController.add(_discoveredPeers);
      } else {
        timer.cancel();
      }
    });
  }

  /// Synchronize all offline queued messages with central backend
  Future<int> syncQueuedMessages(String backendBaseUrl) async {
    final queued = await getQueuedMessages();
    if (queued.isEmpty) return 0;

    int syncedCount = 0;
    final List<String> successfullySyncedIds = [];

    for (final msg in queued) {
      try {
        final res = await http
            .post(
              Uri.parse('$backendBaseUrl/api/offline/relay'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({'messages': [msg]}),
            )
            .timeout(const Duration(seconds: 5));

        if (res.statusCode == 200) {
          syncedCount++;
          successfullySyncedIds.add(msg['sos_id'].toString());
        }
      } catch (_) {
        // Still offline, will retry later
      }
    }

    // Remove successfully synchronized items from queue
    if (successfullySyncedIds.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final List<String> current = prefs.getStringList(_storageKey) ?? [];
      current.removeWhere((item) {
        try {
          final decoded = json.decode(item);
          return successfullySyncedIds.contains(decoded['sos_id']);
        } catch (_) {
          return false;
        }
      });
      await prefs.setStringList(_storageKey, current);
    }

    return syncedCount;
  }
}
