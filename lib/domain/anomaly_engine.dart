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

  // Sliding window of screen-off samples
  final List<TelemetrySample> _screenOffBuffer = [];
  static const int _consecutiveSpikeThreshold = 3;

  double get baselineIdleMa => _baselineIdleMa;

  /// Updates baseline idle current using Exponentially Weighted Moving Average (EWMA)
  /// when the device is confirmed idle and screen-off.
  void updateBaseline(int currentMa, bool isScreenOn, bool isCharging) {
    if (!isScreenOn && !isCharging && currentMa > 0 && currentMa < 250) {
      _baselineIdleMa = (_alpha * currentMa) + ((1.0 - _alpha) * _baselineIdleMa);
    }
  }

  /// Evaluates an incoming sample for drain anomalies.
  /// Returns an [AnomalyIncident] if an anomaly trigger is met, otherwise null.
  AnomalyIncident? evaluateSample(TelemetrySample sample) {
    if (sample.isCharging) {
      _screenOffBuffer.clear();
      return null;
    }

    if (sample.isScreenOn) {
      _screenOffBuffer.clear();
      return null;
    }

    // Device is on battery and screen is OFF
    _screenOffBuffer.add(sample);
    if (_screenOffBuffer.length > 10) {
      _screenOffBuffer.removeAt(0);
    }

    updateBaseline(sample.currentMilliamps, sample.isScreenOn, sample.isCharging);

    // Heuristic 1: Critical Thermal + Heavy Current Spike
    // Current > 750mA with thermal status >= 2 (MODERATE) or temp > 38.5C
    if (sample.currentMilliamps >= 750 && (sample.thermalStatus >= 2 || sample.temperatureCelsius >= 38.5)) {
      return AnomalyIncident(
        startTime: sample.timestamp,
        severity: AnomalySeverity.critical,
        peakCurrentMa: sample.currentMilliamps,
        maxTemperatureCelsius: sample.temperatureCelsius,
        culpritThread: 'Stuck CPU Core / Heavy Worker',
        diagnosis: 'Sustained severe discharge (${sample.currentMilliamps}mA) with thermal throttling. A background loop is spinning an entire CPU core.',
        recommendedAction: 'Inspect active threads or restart device',
      );
    }

    // Heuristic 2: Screen-off runaway drain over consecutive samples
    if (_screenOffBuffer.length >= _consecutiveSpikeThreshold) {
      final recentSamples = _screenOffBuffer.sublist(_screenOffBuffer.length - _consecutiveSpikeThreshold);
      final allSpiking = recentSamples.every((s) => s.currentMilliamps >= 400);

      if (allSpiking) {
        final peakMa = recentSamples.map((s) => s.currentMilliamps).reduce(max);
        final maxTemp = recentSamples.map((s) => s.temperatureCelsius).reduce(max);

        if (peakMa >= 600) {
          return AnomalyIncident(
            startTime: recentSamples.first.timestamp,
            severity: AnomalySeverity.moderate,
            peakCurrentMa: peakMa,
            maxTemperatureCelsius: maxTemp,
            diagnosis: 'High idle discharge sustained while display is sleeping (${peakMa}mA). A background service or wakelock is preventing deep sleep.',
            recommendedAction: 'Check running services or isolate culprit package',
          );
        } else {
          return AnomalyIncident(
            startTime: recentSamples.first.timestamp,
            severity: AnomalySeverity.mild,
            peakCurrentMa: peakMa,
            maxTemperatureCelsius: maxTemp,
            diagnosis: 'Elevated screen-off drain (${peakMa}mA vs baseline ${_baselineIdleMa.round()}mA). Background sync or sensor active.',
            recommendedAction: 'Monitor background sync frequency',
          );
        }
      }
    }

    return null;
  }
}
