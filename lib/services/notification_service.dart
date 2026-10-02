import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../domain/models/anomaly_incident.dart';

/// Notification Service for issuing alert notifications on runaway battery drain.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      settings: initSettings,
    );
    _initialized = true;
  }

  Future<void> showAnomalyNotification(AnomalyIncident incident) async {
    const androidDetails = AndroidNotificationDetails(
      'power_warden_alerts',
      'PowerWarden Alerts',
      channelDescription: 'Alerts for sudden battery drain anomalies',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    const notificationDetails = NotificationDetails(android: androidDetails);

    final title = '⚡ ${incident.severity.name.toUpperCase()} Idle Drain Detected';
    final body = '${incident.peakCurrentMa}mA discharge rate. ${incident.diagnosis}';

    await _notificationsPlugin.show(
      id: incident.hashCode,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
    );
  }
}
