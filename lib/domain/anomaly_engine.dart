import 'dart:math';
import 'models/anomaly_incident.dart';
import 'models/telemetry_sample.dart';

/// Heuristic Anomaly Detection Engine.
/// Distinguishes between:
/// 1. Real-time incident detection & logging (NEVER capped or dropped).
/// 2. Notification alerting with urgency escalation:
///    - Critical emergencies (overheating / thermal danger) ALERT IMMEDIATELY.
///    - Moderate / mild anomalies use a 3-minute alert cooldown so notifications don't buzz continuously.
class AnomalyEngine {
  // EWMA Baseline current estimation
  double _baselineIdleMa = 80.0;
  static const double _alpha = 0.05;

  // Sliding window of samples
  final List<TelemetrySample> _recentSamples = [];
  static const int _consecutiveSpikeThreshold = 2; // 2 ticks = 10s

  double get baselineIdleMa => _baselineIdleMa;

  /// Updates baseline idle current using Exponentially Weighted Moving Average (EWMA)
  void updateBaseline(int currentMa, bool isScreenOn, bool isCharging) {
    if (!isCharging && currentMa > 0 && currentMa < 250) {
      _baselineIdleMa = (_alpha * currentMa) + ((1.0 - _alpha) * _baselineIdleMa);
    }
  }

  DateTime? _lastAlertNotificationTime;
  AnomalySeverity? _lastAlertSeverity;
  static const Duration _nonCriticalAlertCooldown = Duration(minutes: 3);

  /// Evaluates an incoming sample for drain anomalies.
  /// Logs incidents to the Sentinel Log and decides whether to post a notification alert.
  AnomalyIncident? evaluateSample(TelemetrySample sample) {
    if (sample.isCharging) {
      _recentSamples.clear();
      return null;
    }

    _recentSamples.add(sample);
    if (_recentSamples.length > 15) {
      _recentSamples.removeAt(0);
    }

    updateBaseline(sample.currentMilliamps, sample.isScreenOn, sample.isCharging);

    // --- Heuristic 1: Critical Thermal + Heavy Current Spike ---
    // Immediate danger: Current >= 750mA and thermal status >= 2 or temp >= 38.5C
    if (sample.currentMilliamps >= 750 && (sample.thermalStatus >= 2 || sample.temperatureCelsius >= 38.5)) {
      return AnomalyIncident(
        startTime: sample.timestamp,
        severity: AnomalySeverity.critical,
        peakCurrentMa: sample.currentMilliamps,
        maxTemperatureCelsius: sample.temperatureCelsius,
        culpritThread: 'Stuck CPU Core / Heavy Worker',
        diagnosis: 'Sustained severe discharge (${sample.currentMilliamps}mA) with thermal elevation. High power burn.',
        recommendedAction: 'Inspect active threads or restart device',
      );
    }

    // --- Heuristic 2: Active or Screen-Off Runaway Drain (>450mA sustained) ---
    if (_recentSamples.length >= _consecutiveSpikeThreshold) {
      final window = _recentSamples.sublist(_recentSamples.length - _consecutiveSpikeThreshold);
      final allSpiking = window.every((s) => s.currentMilliamps >= 500);

      if (allSpiking) {
        final peakMa = window.map((s) => s.currentMilliamps).reduce(max);
        final maxTemp = window.map((s) => s.temperatureCelsius).reduce(max);

        if (peakMa >= 700) {
          return AnomalyIncident(
            startTime: window.first.timestamp,
            severity: AnomalySeverity.moderate,
            peakCurrentMa: peakMa,
            maxTemperatureCelsius: maxTemp,
            diagnosis: 'High discharge rate sustained ($peakMa mA). A background service or wakelock is burning battery.',
            recommendedAction: 'Check active app energy list',
          );
        }
      }
    }

    return null;
  }

  /// Evaluates whether an [AnomalyIncident] warrants buzzing the user's notification bar right now.
  /// - CRITICAL (overheating, severe burn): ALWAYS alerts instantly (bypasses cooldown).
  /// - MODERATE / MILD: Alerts immediately if severity escalated, or throttles to 3-min cooldown.
  bool shouldAlertNotification(AnomalyIncident incident) {
    final now = DateTime.now();

    // Critical incidents always alert immediately
    if (incident.severity == AnomalySeverity.critical) {
      _lastAlertNotificationTime = now;
      _lastAlertSeverity = incident.severity;
      return true;
    }

    // If escalating from mild to moderate, alert immediately
    if (_lastAlertSeverity == AnomalySeverity.mild && incident.severity == AnomalySeverity.moderate) {
      _lastAlertNotificationTime = now;
      _lastAlertSeverity = incident.severity;
      return true;
    }

    // Check 3-minute cooldown for repeated non-critical alerts
    if (_lastAlertNotificationTime == null ||
        now.difference(_lastAlertNotificationTime!) >= _nonCriticalAlertCooldown) {
      _lastAlertNotificationTime = now;
      _lastAlertSeverity = incident.severity;
      return true;
    }

    return false;
  }
}
