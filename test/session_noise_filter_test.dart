import 'package:flutter_test/flutter_test.dart';
import 'package:power_warden/domain/drain_thresholds.dart';
import 'package:power_warden/domain/models/power_session.dart';
import 'package:power_warden/domain/session_noise_filter.dart';

/// History must not read as noise: sub-minute blips and 0%-movement cycles are
/// filtered out at read time so records already on disk from older builds stop
/// polluting the History tab.
void main() {
  group('SessionNoiseFilter', () {
    test('drops a 45-second discharge blip', () {
      final blip = _session(
        type: 'discharging',
        duration: const Duration(seconds: 45),
        startLevel: 80,
        endLevel: 79,
      );

      expect(SessionNoiseFilter.isMeaningful(blip), isFalse);
    });

    test('drops a long session that moved no battery', () {
      final flat = _session(
        type: 'discharging',
        duration: const Duration(minutes: 8),
        startLevel: 80,
        endLevel: 80,
      );

      expect(SessionNoiseFilter.isMeaningful(flat), isFalse);
    });

    test('keeps a 2-minute, 1% discharge cycle', () {
      final real = _session(
        type: 'discharging',
        duration: DrainThresholds.minSessionDuration,
        startLevel: 80,
        endLevel: 79,
      );

      expect(SessionNoiseFilter.isMeaningful(real), isTrue);
    });

    test('drops a 1-minute standby rest', () {
      final nap = _session(
        type: 'standby',
        duration: const Duration(minutes: 1),
        startLevel: 70,
        endLevel: 70,
      );

      expect(SessionNoiseFilter.isMeaningful(nap), isFalse);
    });

    test('keeps a 10-minute standby rest even without level movement', () {
      final rest = _session(
        type: 'standby',
        duration: DrainThresholds.minStandbyDuration,
        startLevel: 70,
        endLevel: 70,
      );

      expect(SessionNoiseFilter.isMeaningful(rest), isTrue);
    });

    test('filters a mixed list down to the real cycles', () {
      final sessions = [
        _session(
          type: 'discharging',
          duration: const Duration(seconds: 30),
          startLevel: 90,
          endLevel: 89,
        ),
        _session(
          type: 'discharging',
          duration: const Duration(minutes: 42),
          startLevel: 89,
          endLevel: 76,
        ),
        _session(
          type: 'charging',
          duration: const Duration(minutes: 3),
          startLevel: 76,
          endLevel: 76,
        ),
        _session(
          type: 'charging',
          duration: const Duration(minutes: 25),
          startLevel: 76,
          endLevel: 92,
        ),
      ];

      final kept = SessionNoiseFilter.meaningful(sessions);

      expect(kept, hasLength(2));
      expect(kept.map((s) => s.startBatteryLevel), containsAll([89, 76]));
    });
  });
}

PowerSession _session({
  required String type,
  required Duration duration,
  required int startLevel,
  required int endLevel,
}) {
  final start = DateTime.now().subtract(duration);
  return PowerSession(
    id: '${type}_${start.millisecondsSinceEpoch}',
    type: type,
    startTime: start,
    endTime: DateTime.now(),
    startBatteryLevel: startLevel,
    endBatteryLevel: endLevel,
    totalMahDelta: 15,
    peakMa: 400,
    peakWatts: 1.6,
    minTempCelsius: 31.0,
    maxTempCelsius: 34.0,
  );
}
