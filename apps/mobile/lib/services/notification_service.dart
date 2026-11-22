// services/notification_service.dart
import 'package:flutter/foundation.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  Future<void> init() async {}

  Future<void> showSosAlert({required String title, required String body}) async {
    debugPrint('[NOTIFICATION ALERT] $title: $body');
  }
}
