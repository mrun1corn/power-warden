import 'package:flutter_test/flutter_test.dart';

int computeMedianCurrent(List<int> samples) {
  final sorted = List<int>.from(samples)..sort();
  return sorted[sorted.length ~/ 2];
}

void main() {
  group('3-Point Median Noise Filter Tests', () {
    test('filters out single transient cellular transmission spike', () {
      // 120mA normal, 950mA transient cellular burst, 125mA normal
      final samples = [120, 950, 125];
      final filtered = computeMedianCurrent(samples);
      expect(filtered, 125);
    });

    test('retains steady high current', () {
      // Sustained drain across all 3 windows
      final samples = [600, 620, 610];
      final filtered = computeMedianCurrent(samples);
      expect(filtered, 610);
    });

    test('filters out transient negative charging glitch', () {
      final samples = [350, -500, 360];
      final filtered = computeMedianCurrent(samples);
      expect(filtered, 350);
    });
  });
}
