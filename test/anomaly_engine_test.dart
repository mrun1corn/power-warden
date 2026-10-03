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

    test('ignores screen on samples', () {
      final sample = TelemetrySample(
        timestamp: DateTime.now(),
        batteryLevel: 80,
        currentMilliamps: 200, // Normal usage
        temperatureCelsius: 34.0,
        thermalStatus: 0,
        isScreenOn: true,
        isCharging: false,
        voltageMv: 3900,
      );

      final anomaly = engine.evaluateSample(sample);
      expect(anomaly, isNull);
    });

    test('triggers Critical Anomaly on high drain with elevated thermal status', () {
      final sample = TelemetrySample(
        timestamp: DateTime.now(),
        batteryLevel: 65,
        currentMilliamps: 850, // Extreme drain
        temperatureCelsius: 41.0, // High heat
        thermalStatus: 3, // SEVERE
        isScreenOn: false,
        isCharging: false,
        voltageMv: 3800,
      );

      final anomaly = engine.evaluateSample(sample);
      expect(anomaly, isNotNull);
      expect(anomaly!.severity, AnomalySeverity.critical);
      expect(anomaly.peakCurrentMa, 850);
    });

    test('triggers Moderate Anomaly on consecutive screen-off spikes', () {
      final freshEngine = AnomalyEngine();
      final now = DateTime.now();

      // Send 2 consecutive high-drain samples
      freshEngine.evaluateSample(TelemetrySample(
        timestamp: now.subtract(const Duration(minutes: 1)),
        batteryLevel: 69,
        currentMilliamps: 720,
        temperatureCelsius: 35.2,
        thermalStatus: 0,
        isScreenOn: false,
        isCharging: false,
        voltageMv: 3940,
      ));

      final anomaly = freshEngine.evaluateSample(TelemetrySample(
        timestamp: now,
        batteryLevel: 69,
        currentMilliamps: 740,
        temperatureCelsius: 35.4,
        thermalStatus: 0,
        isScreenOn: false,
        isCharging: false,
        voltageMv: 3930,
      ));

      expect(anomaly, isNotNull);
      expect(anomaly!.severity, AnomalySeverity.moderate);
      expect(anomaly.peakCurrentMa, 740);
    });
  });
}
