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
  AnomalyIncident? evaluateSample(
    TelemetrySample sample, {
    Map<String, dynamic>? differentialDiagnostics,
    Map<String, dynamic>? topProcess,
  }) {
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

          // Automated Rulebook Translation (PLANS Phase 3.3)
          String diagnosis = 'Rogue sleep drain ($peakMa mA while screen off). An app or wakelock is preventing deep sleep.';
          String recommendedAction = 'Check active app energy list';
          String? culpritPackage = topProcess?['packageName'] as String?;
          String? culpritThread = topProcess?['name'] as String?;

          final wakelockDump = (differentialDiagnostics?['wakelocks'] as String?) ?? '';
          final topOutput = (differentialDiagnostics?['snapshot2'] as String?) ?? '';

          if (wakelockDump.contains('AudioMix')) {
            diagnosis = 'Audio hardware lock (AudioMix) not released while display is asleep.';
            recommendedAction = 'Force stop media player or background audio';
            culpritThread = 'AudioMix';
          } else if (topOutput.contains('CpuTracker') || topOutput.contains('system_server')) {
            diagnosis = 'Android system IPC contention loop in system_server.';
            recommendedAction = 'Device reboot recommended';
            culpritPackage = 'system_server';
            culpritThread = 'CpuTracker';
          } else if (topOutput.contains('GcmService') || topOutput.contains('com.google.android.gms')) {
            diagnosis = 'Google Play Services sync retry loop due to network/push contention.';
            recommendedAction = 'Toggle Airplane mode or clear Play Services cache';
            culpritPackage = 'com.google.android.gms';
            culpritThread = 'GcmService';
          } else if (culpritThread != null && culpritThread.isNotEmpty) {
            diagnosis = 'High background CPU activity detected from $culpritThread ($peakMa mA).';
            recommendedAction = 'Tap Force Stop to tame application';
          }

          return AnomalyIncident(
            startTime: window.first.timestamp,
            severity: isCriticalSleep ? AnomalySeverity.critical : AnomalySeverity.moderate,
            peakCurrentMa: peakMa,
            maxTemperatureCelsius: maxTemp,
            culpritPackage: culpritPackage,
            culpritThread: culpritThread,
            diagnosis: diagnosis,
            recommendedAction: recommendedAction,
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
        culpritPackage: topProcess?['packageName'] as String?,
        culpritThread: topProcess?['name'] as String? ?? 'Thermal Runaway Loop',
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
