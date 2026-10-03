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

  Future<void> showAnomalyNotification(
    AnomalyIncident incident, {
    String? topAppName,
    double? topAppCpu,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'power_warden_alerts',
      'PowerWarden Alerts',
      channelDescription: 'Alerts for sudden battery drain anomalies',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    const notificationDetails = NotificationDetails(android: androidDetails);

    final title = '⚡ Critical Battery Drain (${incident.peakCurrentMa} mA)';
    final String body;

    final culprit = incident.culpritPackage ?? incident.culpritThread;
    if (culprit != null && culprit.isNotEmpty && !culprit.contains('Stuck CPU')) {
      body = 'Rogue app: $culprit · Burning power in background.';
    } else if (topAppName != null && topAppName.isNotEmpty) {
      final cpuStr = topAppCpu != null && topAppCpu > 0 ? ' (${topAppCpu.toStringAsFixed(1)}% CPU)' : '';
      body = 'Top Consumer: $topAppName$cpuStr · High power burn.';
    } else {
      body = '${incident.peakCurrentMa} mA sustained draw with thermal elevation.';
    }

    await _notificationsPlugin.show(
      id: incident.hashCode,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
    );
  }
}
