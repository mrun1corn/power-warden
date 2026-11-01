import 'dart:math';
import 'drain_thresholds.dart';
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
  static const int _consecutiveSpikeThreshold = DrainThresholds.consecutiveSpikeSamples;

  // ── Incident deduplication & resolution ─────────────────────────────
  // One sustained rogue-drain event should produce ONE incident, not one
  // per detection tick. A new incident of the same category is suppressed
  // while the previous one is younger than [incidentCooldown]; the previous
  // incident is closed (endTime set) once drain subsides.
  static const Duration incidentCooldown = DrainThresholds.incidentCooldown;
  AnomalyIncident? _lastSleepIncident;
  AnomalyIncident? _lastActiveIncident;

  double get baselineIdleMa => _baselineIdleMa;

  /// Closes any open incident (drain subsided) — call on every calm sample.
  AnomalyIncident? resolveOpenIncidents(TelemetrySample sample) {
    AnomalyIncident? closed;
    if (_lastSleepIncident != null && _lastSleepIncident!.endTime == null) {
      final drainSettled = sample.isCharging ||
          (sample.isScreenOn) ||
          (sample.currentMilliamps < DrainThresholds.sleepAnomalyMa);
      if (drainSettled) {
        closed = _lastSleepIncident!.copyWith(endTime: sample.timestamp);
        _lastSleepIncident = closed;
      }
    }
    if (_lastActiveIncident != null && _lastActiveIncident!.endTime == null) {
      final settled =
          sample.currentMilliamps < DrainThresholds.activeAnomalyMa ||
          sample.temperatureCelsius < 42.0;
      if (settled) {
        final closedActive =
            _lastActiveIncident!.copyWith(endTime: sample.timestamp);
        _lastSleepIncident ??= closedActive;
        closed ??= closedActive;
        _lastActiveIncident = closedActive;
      }
    }
    return closed;
  }

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
        final allSpiking = window.every((s) => !s.isScreenOn && s.currentMilliamps >= DrainThresholds.sleepAnomalyMa);

        if (allSpiking) {
          final peakMa = window.map((s) => s.currentMilliamps).reduce(max);
          final maxTemp = window.map((s) => s.temperatureCelsius).reduce(max);

          // Dedup: suppress re-fire while the previous sleep incident is
          // younger than the cooldown and still open (same sustained event).
          final last = _lastSleepIncident;
          final withinCooldown = last != null &&
              sample.timestamp.difference(last.startTime) < incidentCooldown;
          if (withinCooldown && last.endTime == null) {
            // Same ongoing event — update peak figures silently, no new log.
            _lastSleepIncident = last.copyWith(
              peakCurrentMa: peakMa > last.peakCurrentMa ? peakMa : last.peakCurrentMa,
              maxTemperatureCelsius:
                  maxTemp > last.maxTemperatureCelsius ? maxTemp : last.maxTemperatureCelsius,
            );
            return null;
          }

          // Critical sleep drain: Screen off but drawing 550mA+ or heating up
          final isCriticalSleep =
              peakMa >= DrainThresholds.sleepCriticalMa ||
              maxTemp >= DrainThresholds.sleepCriticalTempC;

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

          return _lastSleepIncident = AnomalyIncident(
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
    // Active screen (120Hz OLED, 5G, CPU) legitimately consumes 400-900mA.
    // Strictly require extreme physical draw (>1,600mA) AND dangerous battery temperature (>= 42°C)
    // to avoid false emergency alarms while user is simply using the phone.
    if (sample.currentMilliamps >= DrainThresholds.activeAnomalyMa &&
        (sample.thermalStatus >= DrainThresholds.thermalModerate ||
            sample.temperatureCelsius >= 42.0)) {
      // Dedup: one incident per sustained thermal event
      final last = _lastActiveIncident;
      final withinCooldown = last != null &&
          sample.timestamp.difference(last.startTime) < incidentCooldown;
      if (withinCooldown && last.endTime == null) {
        _lastActiveIncident = last.copyWith(
          peakCurrentMa: sample.currentMilliamps > last.peakCurrentMa
              ? sample.currentMilliamps
              : last.peakCurrentMa,
          maxTemperatureCelsius: sample.temperatureCelsius > last.maxTemperatureCelsius
              ? sample.temperatureCelsius
              : last.maxTemperatureCelsius,
        );
        return null;
      }

      return _lastActiveIncident = AnomalyIncident(
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
