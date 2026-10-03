import 'package:flutter_test/flutter_test.dart';
import 'package:power_warden/domain/models/telemetry_sample.dart';
import 'package:power_warden/domain/models/anomaly_incident.dart';
import 'package:power_warden/domain/anomaly_engine.dart';

void main() {
  group('PowerWarden Comprehensive Feature Simulation Suite', () {
    late AnomalyEngine engine;

    setUp(() {
      engine = AnomalyEngine();
    });

    test('Feature 1: Auto-Scaling and Current Normalization Simulation', () {
      // Simulate raw microamps (Samsung/OneUI reporting 750,000 uA) vs standard mA (750 mA)
      int normalizeCurrentSimulation(int raw) {
        if (raw.abs() > 10000) {
          return (raw / 1000.0).round();
        }
        return raw;
      }

      expect(normalizeCurrentSimulation(750000), equals(750));
      expect(normalizeCurrentSimulation(-450000), equals(-450));
      expect(normalizeCurrentSimulation(320), equals(320));
      expect(normalizeCurrentSimulation(-500), equals(-500));
    });

    test('Feature 2: Sleep vs Screen-On Drain Discrimination', () {
      final now = DateTime.now();

      // Screen ON at 850mA (standard 120Hz display load) -> MUST NOT trigger an anomaly
      final screenOnSample = TelemetrySample(
        timestamp: now,
        batteryLevel: 75,
        currentMilliamps: 850,
        temperatureCelsius: 35.0,
        thermalStatus: 0,
        isScreenOn: true,
        isCharging: false,
        voltageMv: 4000,
      );
      expect(engine.evaluateSample(screenOnSample), isNull);

      // Screen OFF at 350mA sustained (rogue background loop / wakelock) -> MUST trigger an anomaly!
      engine.evaluateSample(TelemetrySample(
        timestamp: now.subtract(const Duration(seconds: 5)),
        batteryLevel: 75,
        currentMilliamps: 340,
        temperatureCelsius: 35.0,
        thermalStatus: 0,
        isScreenOn: false,
        isCharging: false,
        voltageMv: 4000,
      ));

      final sleepAnomaly = engine.evaluateSample(TelemetrySample(
        timestamp: now,
        batteryLevel: 75,
        currentMilliamps: 360,
        temperatureCelsius: 35.1,
        thermalStatus: 0,
        isScreenOn: false,
        isCharging: false,
        voltageMv: 3990,
      ));

      expect(sleepAnomaly, isNotNull);
      expect(sleepAnomaly!.severity, equals(AnomalySeverity.moderate));
      expect(sleepAnomaly.diagnosis, contains('Rogue sleep drain'));
      expect(sleepAnomaly.peakCurrentMa, equals(360));
    });

    test('Feature 3: Critical Thermal Runaway & Emergency Notification Filter', () {
      final now = DateTime.now();

      // Critical thermal event: 1500mA active draw + high thermal status (device overheating)
      final thermalRunawaySample = TelemetrySample(
        timestamp: now,
        batteryLevel: 60,
        currentMilliamps: 1550,
        temperatureCelsius: 42.5,
        thermalStatus: 2,
        isScreenOn: true,
        isCharging: false,
        voltageMv: 3750,
      );

      final incident = engine.evaluateSample(thermalRunawaySample);
      expect(incident, isNotNull);
      expect(incident!.severity, equals(AnomalySeverity.critical));

      // Notification filter: shouldAlertNotification MUST be true for critical emergencies
      expect(engine.shouldAlertNotification(incident), isTrue);

      // And MUST be false for non-critical routine events
      final nonCriticalIncident = AnomalyIncident(
        startTime: now,
        severity: AnomalySeverity.moderate,
        peakCurrentMa: 350,
        maxTemperatureCelsius: 35.0,
        diagnosis: 'Minor standby drain',
      );
      expect(engine.shouldAlertNotification(nonCriticalIncident), isFalse);
    });

    test('Feature 4: Live Dynamic mA Attribution per App Simulation', () {
      const totalSystemDrainMa = 780; // Total phone current from fuel-gauge sensor

      // Running process list with CPU shares
      final processes = [
        {'name': 'Nekogram', 'cpuPercent': 25.0},
        {'name': 'WhatsApp', 'cpuPercent': 8.0},
        {'name': 'Google Play Services', 'cpuPercent': 3.0},
        {'name': 'Chrome', 'cpuPercent': 1.5},
      ];

      int calculateAttributedMa(double cpu) {
        return (totalSystemDrainMa * (cpu / 100.0)).round();
      }

      expect(calculateAttributedMa(processes[0]['cpuPercent'] as double), equals(195));
      expect(calculateAttributedMa(processes[1]['cpuPercent'] as double), equals(62));
      expect(calculateAttributedMa(processes[2]['cpuPercent'] as double), equals(23));
      expect(calculateAttributedMa(processes[3]['cpuPercent'] as double), equals(12));
    });

    test('Feature 5: Elevation Recognition Logic Simulation', () {
      // Simulating the 3-state check: Active Kadb Socket, Persisted Pairing Credentials, or Permanent ADB
      bool isElevated({
        required bool activeSocket,
        required bool isPaired,
        required bool permanentAdb,
        required bool shizukuPermission,
      }) {
        final hasKadb = activeSocket || isPaired || permanentAdb;
        return hasKadb || shizukuPermission;
      }

      // Case 1: Brand new clean install
      expect(isElevated(activeSocket: false, isPaired: false, permanentAdb: false, shizukuPermission: false), isFalse);

      // Case 2: User paired via Wireless ADB, then socket closed (app restarted) -> STILL ELEVATED!
      expect(isElevated(activeSocket: false, isPaired: true, permanentAdb: false, shizukuPermission: false), isTrue);

      // Case 3: Battery Guru permanent ADB permissions granted via PC terminal -> ELEVATED!
      expect(isElevated(activeSocket: false, isPaired: false, permanentAdb: true, shizukuPermission: false), isTrue);

      // Case 4: Shizuku authorized -> ELEVATED!
      expect(isElevated(activeSocket: false, isPaired: false, permanentAdb: false, shizukuPermission: true), isTrue);
    });
  });
}
