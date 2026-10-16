/// Standardized, reusable formatters across PowerWarden UI tabs.
class PowerFormatters {
  PowerFormatters._();

  /// Formats exact duration cleanly across all screens:
  /// e.g. "45s", "2m 15s", "18 min", "1h 12m"
  static String duration(Duration d) {
    final secs = d.inSeconds;
    if (secs < 60) {
      return '${secs}s';
    } else if (secs < 3600) {
      final mins = secs ~/ 60;
      final remSecs = secs % 60;
      return remSecs > 0 ? '${mins}m ${remSecs}s' : '$mins min';
    } else {
      final hours = secs ~/ 3600;
      final remMins = (secs % 3600) ~/ 60;
      return remMins > 0 ? '${hours}h ${remMins}m' : '${hours}h';
    }
  }

  /// Formats human-friendly local timestamps paired with relative time:
  /// e.g. "12:41 AM (32m ago)", "Yesterday 11:20 PM"
  static String relativeTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    final minute = local.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute $ampm';

    final now = DateTime.now();
    final diff = now.difference(local);

    if (diff.inMinutes < 1) {
      return 'Just now ($timeStr)';
    } else if (diff.inMinutes < 60) {
      return '$timeStr (${diff.inMinutes}m ago)';
    } else if (diff.inHours < 24 && local.day == now.day) {
      return '$timeStr (${diff.inHours}h ago)';
    } else if (diff.inHours < 48) {
      return 'Yesterday $timeStr';
    } else {
      return '${local.month}/${local.day} $timeStr';
    }
  }

  /// Formats physical current flow with polarity sign:
  /// e.g. "+3120 mA" (charging) or "-450 mA" (discharging)
  static String currentFlow(int currentMa, {bool isCharging = false}) {
    final absMa = currentMa.abs();
    return isCharging ? '+$absMa mA' : '-$absMa mA';
  }

  /// Formats hourly battery burn/charge velocity rate:
  /// e.g. "~8.4%/hr"
  static String burnRatePerHour(int currentMa, {double capacityMah = 4500.0}) {
    final absMa = currentMa.abs();
    final rate = ((absMa / capacityMah) * 100.0).toStringAsFixed(1);
    return '~$rate%/hr';
  }

  /// Formats physical wattage in Watts:
  /// e.g. "18.5W", "2.1W"
  static String wattage(int millivolts, int milliamps) {
    final watts = (millivolts / 1000.0) * (milliamps.abs() / 1000.0);
    return '${watts.toStringAsFixed(1)}W';
  }
}
