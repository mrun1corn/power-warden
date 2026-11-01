import 'package:flutter_test/flutter_test.dart';
import 'package:power_warden/domain/anomaly_engine.dart';
import 'package:power_warden/domain/drain_thresholds.dart';
import 'package:power_warden/domain/models/anomaly_incident.dart';
import 'package:power_warden/domain/models/telemetry_sample.dart';

/// Regression suite for the current-sign contract.
///
/// `BatteryProbe.normalizeCurrent` guarantees **positive mA = discharging**.
/// The engine compares those signed values against drain thresholds, so a
/// polarity regression silently disables detection entirely. These tests feed
/// the engine exactly what the probe now emits (positive while draining,
/// negative while charging) and assert that real anomalies are still caught.
void main() {
  group('Current sign contract', () {
    test('positive mA while discharging is treated as drain', () {
      final engine = AnomalyEngine();
      final first = _sample(secondsAgo: 20, currentMa: 900, screenOn: false);
      final second = _sample(secondsAgo: 10, currentMa: 950, screenOn: false);

      expect(engine.evaluateSample(first), isNull);
      final incident = engine.evaluateSample(second);

      expect(incident, isNotNull, reason: 'sustained 900+ mA asleep must fire');
      expect(incident!.severity, AnomalySeverity.critical);
      expect(incident.peakCurrentMa, 950);
    });

    test('negative mA (charging) never produces an incident', () {
      final engine = AnomalyEngine();
      final sample = _sample(
        secondsAgo: 5,
        currentMa: -900,
        screenOn: false,
        isCharging: true,
      );

      expect(engine.evaluateSample(sample), isNull);
      expect(engine.resolveOpenIncidents(sample), isNull);
    });

    test('the old buggy negative-while-draining input no longer detects', () {
      // Documents the failure mode this suite exists to prevent: if the probe
      // ever emits negative mA for a discharging phone, the engine goes silent.
      final engine = AnomalyEngine();
      engine.evaluateSample(_sample(secondsAgo: 20, currentMa: -900, screenOn: false));
      final incident = engine.evaluateSample(
        _sample(secondsAgo: 10, currentMa: -950, screenOn: false),
      );

      expect(
        incident,
        isNull,
        reason: 'negative drain values are invisible to threshold comparisons',
      );
    });

    test('a settled sample closes the open sleep incident', () {
      final engine = AnomalyEngine();
      engine.evaluateSample(_sample(secondsAgo: 30, currentMa: 700, screenOn: false));
      engine.evaluateSample(_sample(secondsAgo: 20, currentMa: 720, screenOn: false));

      final closed = engine.resolveOpenIncidents(
        _sample(secondsAgo: 10, currentMa: 40, screenOn: false),
      );

      expect(closed, isNotNull);
      expect(closed!.endTime, isNotNull);
    });
  });

  group('DrainThresholds are the only source of truth', () {
    test('engine uses the shared sleep threshold', () {
      final engine = AnomalyEngine();
      final below = DrainThresholds.sleepAnomalyMa - 20;
      engine.evaluateSample(_sample(secondsAgo: 20, currentMa: below, screenOn: false));
      expect(
        engine.evaluateSample(
          _sample(secondsAgo: 10, currentMa: below, screenOn: false),
        ),
        isNull,
        reason: 'draw under sleepAnomalyMa is not an anomaly',
      );

      final at = DrainThresholds.sleepAnomalyMa + 20;
      engine.evaluateSample(_sample(secondsAgo: 20, currentMa: at, screenOn: false));
      expect(
        engine.evaluateSample(
          _sample(secondsAgo: 10, currentMa: at, screenOn: false),
        ),
        isNotNull,
        reason: 'draw over sleepAnomalyMa must fire',
      );
    });

    test('threshold ordering is sane', () {
      expect(
        DrainThresholds.sleepAnomalyMa,
        lessThan(DrainThresholds.sleepCriticalMa),
      );
      expect(
        DrainThresholds.sleepAnomalyMa,
        lessThan(DrainThresholds.activeHeavyMa),
      );
      expect(
        DrainThresholds.activeHeavyMa,
        lessThan(DrainThresholds.activeCriticalMa),
      );
      expect(
        DrainThresholds.activeCriticalMa,
        lessThan(DrainThresholds.activeAnomalyMa),
      );
      expect(
        DrainThresholds.activeAnomalyMa,
        lessThan(DrainThresholds.activeAbsoluteMa),
      );
    });
  });
}

TelemetrySample _sample({
  required int secondsAgo,
  required int currentMa,
  required bool screenOn,
  bool isCharging = false,
}) {
  return TelemetrySample(
    timestamp: DateTime.now().subtract(Duration(seconds: secondsAgo)),
    batteryLevel: 80,
    currentMilliamps: currentMa,
    temperatureCelsius: 33.0,
    thermalStatus: 0,
    isScreenOn: screenOn,
    isCharging: isCharging,
    voltageMv: 4000,
  );
}
