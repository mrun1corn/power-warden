import 'drain_thresholds.dart';
import 'models/power_session.dart';

/// Decides whether a recorded session is worth showing in History.
///
/// Applied at **read** time, not just at write time, because sessions are never
/// pruned from disk — without this, every sub-minute blip written by an older
/// build would stay visible forever.
class SessionNoiseFilter {
  SessionNoiseFilter._();

  /// True when [session] represents a real charge/discharge/standby interval.
  ///
  /// - standby: must run at least [DrainThresholds.minStandbyDuration]
  /// - charging / discharging: must run at least
  ///   [DrainThresholds.minSessionDuration] **and** move the battery by at least
  ///   [DrainThresholds.minSessionDeltaPercent]
  static bool isMeaningful(PowerSession session) {
    final isStandby = session.type == 'standby';
    final minDuration = isStandby
        ? DrainThresholds.minStandbyDuration
        : DrainThresholds.minSessionDuration;

    if (session.duration < minDuration) return false;
    if (isStandby) return true;

    final delta = (session.endBatteryLevel - session.startBatteryLevel).abs();
    return delta >= DrainThresholds.minSessionDeltaPercent;
  }

  /// Filters a session list down to the meaningful entries.
  static List<PowerSession> meaningful(Iterable<PowerSession> sessions) =>
      sessions.where(isMeaningful).toList();
}
