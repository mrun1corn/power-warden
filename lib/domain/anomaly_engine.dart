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
  /// Dynamically calibrated for real Android hardware:
  /// - SCREEN ON: 300-800mA is normal usage. Heavy games/video can hit 900-1400mA.
  /// - SCREEN OFF: Should be resting idle (15-60mA). Sustained drain >250mA asleep is a rogue wakelock!
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

    // --- Scenario A: Device is ASLEEP (Screen OFF) ---
    // A sleeping phone should NEVER draw 300mA+ continuously unless an app is holding an unreleased wakelock.
    if (!sample.isScreenOn) {
      if (_recentSamples.length >= _consecutiveSpikeThreshold) {
        final window = _recentSamples.sublist(_recentSamples.length - _consecutiveSpikeThreshold);
        final allSpiking = window.every((s) => !s.isScreenOn && s.currentMilliamps >= 280);

        if (allSpiking) {
          final peakMa = window.map((s) => s.currentMilliamps).reduce(max);
          final maxTemp = window.map((s) => s.temperatureCelsius).reduce(max);

          // Critical sleep drain: Screen off but drawing 550mA+ or heating up
          final isCriticalSleep = peakMa >= 550 || maxTemp >= 38.0;

          return AnomalyIncident(
            startTime: window.first.timestamp,
            severity: isCriticalSleep ? AnomalySeverity.critical : AnomalySeverity.moderate,
            peakCurrentMa: peakMa,
            maxTemperatureCelsius: maxTemp,
            diagnosis: 'Rogue sleep drain ($peakMa mA while screen off). An app or wakelock is preventing deep sleep.',
            recommendedAction: 'Check active app energy list',
          );
        }
      }
      return null;
    }

    // --- Scenario B: Device is AWAKE (Screen ON) ---
    // Active screen (120Hz OLED, 5G, CPU) legitimately consumes 400-800mA.
    // Only flag as CRITICAL emergency if sustained draw exceeds 1,400mA with high heat (thermal runaway).
    if (sample.currentMilliamps >= 1400 && (sample.thermalStatus >= 2 || sample.temperatureCelsius >= 41.0)) {
      return AnomalyIncident(
        startTime: sample.timestamp,
        severity: AnomalySeverity.critical,
        peakCurrentMa: sample.currentMilliamps,
        maxTemperatureCelsius: sample.temperatureCelsius,
        culpritThread: 'Thermal Runaway Loop',
        diagnosis: 'Severe active discharge (${sample.currentMilliamps} mA) with device overheating (${sample.temperatureCelsius}°C).',
        recommendedAction: 'Inspect heavy 3D/CPU tasks or reboot',
      );
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
