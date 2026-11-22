// services/notification_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/launcher_icon');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
  }

  Future<void> showSosAlert({required String title, required String body}) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'sos_alerts',
        'SOS Alerts',
        channelDescription: 'Real-time emergency SOS alerts',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
    );
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }
}
