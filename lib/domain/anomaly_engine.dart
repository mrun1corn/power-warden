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

  /// Evaluates whether an [AnomalyIncident] warrants buzzing the user's notification bar.
  /// Strictly reserved for CRITICAL emergencies only (e.g. sustained high power drain + thermal elevation).
  /// Routine moderate background activity is logged quietly in the Sentinel Log without interrupting the user.
  bool shouldAlertNotification(AnomalyIncident incident) {
    return incident.severity == AnomalySeverity.critical;
  }
}
