import 'package:flutter_test/flutter_test.dart';
import 'package:power_warden/domain/anomaly_engine.dart';
import 'package:power_warden/domain/models/anomaly_incident.dart';
import 'package:power_warden/domain/models/telemetry_sample.dart';

void main() {
  group('AnomalyEngine Tests', () {
    late AnomalyEngine engine;

    setUp(() {
      engine = AnomalyEngine();
    });

    test('ignores charging samples', () {
      final sample = TelemetrySample(
        timestamp: DateTime.now(),
        batteryLevel: 80,
        currentMilliamps: -1500, // Charging
        temperatureCelsius: 32.0,
        thermalStatus: 0,
        isScreenOn: false,
        isCharging: true,
        voltageMv: 4200,
      );

      final anomaly = engine.evaluateSample(sample);
      expect(anomaly, isNull);
    });

    test('ignores screen on samples under normal load', () {
      final sample = TelemetrySample(
        timestamp: DateTime.now(),
        batteryLevel: 80,
        currentMilliamps: 850, // Normal active usage
        temperatureCelsius: 34.0,
        thermalStatus: 0,
        isScreenOn: true,
        isCharging: false,
        voltageMv: 3900,
      );

      final anomaly = engine.evaluateSample(sample);
      expect(anomaly, isNull);
    });

    test('triggers Critical Anomaly on severe screen-on thermal runaway', () {
      final sample = TelemetrySample(
        timestamp: DateTime.now(),
        batteryLevel: 80,
        currentMilliamps: 1650,
        temperatureCelsius: 42.5,
        thermalStatus: 2,
        isScreenOn: true,
        isCharging: false,
        voltageMv: 3800,
      );

      final anomaly = engine.evaluateSample(sample);
      expect(anomaly, isNotNull);
      expect(anomaly!.severity, AnomalySeverity.critical);
    });

    test('triggers Rogue Sleep Drain Anomaly on consecutive screen-off spikes', () {
      final freshEngine = AnomalyEngine();
      final now = DateTime.now();

      freshEngine.evaluateSample(TelemetrySample(
        timestamp: now.subtract(const Duration(minutes: 1)),
        batteryLevel: 69,
        currentMilliamps: 320,
        temperatureCelsius: 35.2,
        thermalStatus: 0,
        isScreenOn: false,
        isCharging: false,
        voltageMv: 3940,
      ));

      final anomaly = freshEngine.evaluateSample(TelemetrySample(
        timestamp: now,
        batteryLevel: 69,
        currentMilliamps: 350,
        temperatureCelsius: 35.4,
        thermalStatus: 0,
        isScreenOn: false,
        isCharging: false,
        voltageMv: 3930,
      ));

      expect(anomaly, isNotNull);
      expect(anomaly!.severity, AnomalySeverity.moderate);
      expect(anomaly.peakCurrentMa, 350);
    });
  });
}
