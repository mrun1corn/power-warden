import 'dart:math';
import 'models/anomaly_incident.dart';
import 'models/telemetry_sample.dart';

/// Heuristic Anomaly Detection Engine.
/// Analyzes real-time and background telemetry samples to flag runaway drain loops,
/// thermal throttling spikes, and unreleased wakelocks.
class AnomalyEngine {
  // EWMA Baseline current estimation
  double _baselineIdleMa = 80.0;
  static const double _alpha = 0.05;

  // Sliding window of samples
  final List<TelemetrySample> _recentSamples = [];
  static const int _consecutiveSpikeThreshold = 2; // Trigger faster (2 ticks = 10s)

  double get baselineIdleMa => _baselineIdleMa;

  /// Updates baseline idle current using Exponentially Weighted Moving Average (EWMA)
  /// when the device is confirmed idle.
  void updateBaseline(int currentMa, bool isScreenOn, bool isCharging) {
    if (!isCharging && currentMa > 0 && currentMa < 250) {
      _baselineIdleMa = (_alpha * currentMa) + ((1.0 - _alpha) * _baselineIdleMa);
    }
  }

  // Cooldown timer to prevent repetitive notification buzzing
  DateTime? _lastNotificationTime;
  static const Duration _notificationCooldown = Duration(minutes: 15);

  /// Evaluates an incoming sample for drain anomalies.
  /// Returns an [AnomalyIncident] if an anomaly trigger is met, otherwise null.
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

    final now = DateTime.now();
    final bool canNotify = _lastNotificationTime == null || now.difference(_lastNotificationTime!) > _notificationCooldown;

    // Heuristic 1: Critical Thermal + Heavy Current Spike
    // Current > 750mA with thermal status >= 2 (MODERATE) or temp > 38.5C
    if (sample.currentMilliamps >= 750 && (sample.thermalStatus >= 2 || sample.temperatureCelsius >= 38.5)) {
      if (!canNotify) return null;
      _lastNotificationTime = now;
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

    // Heuristic 2: Active or Screen-Off Runaway Drain (>450mA sustained)
    if (_recentSamples.length >= _consecutiveSpikeThreshold) {
      final window = _recentSamples.sublist(_recentSamples.length - _consecutiveSpikeThreshold);
      final allSpiking = window.every((s) => s.currentMilliamps >= 450);

      if (allSpiking && canNotify) {
        final peakMa = window.map((s) => s.currentMilliamps).reduce(max);
        final maxTemp = window.map((s) => s.temperatureCelsius).reduce(max);

        _lastNotificationTime = now;

        if (peakMa >= 650) {
          return AnomalyIncident(
            startTime: window.first.timestamp,
            severity: AnomalySeverity.moderate,
            peakCurrentMa: peakMa,
            maxTemperatureCelsius: maxTemp,
            diagnosis: 'High discharge rate sustained (${peakMa}mA). A background service or wakelock is burning battery.',
            recommendedAction: 'Check active app energy list',
          );
        } else {
          return AnomalyIncident(
            startTime: window.first.timestamp,
            severity: AnomalySeverity.mild,
            peakCurrentMa: peakMa,
            maxTemperatureCelsius: maxTemp,
            diagnosis: 'Elevated power drain (${peakMa}mA vs baseline ${_baselineIdleMa.round()}mA). App activity detected.',
            recommendedAction: 'Monitor background sync',
          );
        }
      }
    }

    return null;
  }
}
