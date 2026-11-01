/// Single source of truth for every drain threshold in PowerWarden (Dart side).
///
/// Mirrors `android/app/src/main/kotlin/com/mrun1corn/powerwarden/service/DrainThresholds.kt`.
/// Both are asserted by tests — change them together.
///
/// Current values are signed: **positive mA = discharge**, negative = charging.
class DrainThresholds {
  DrainThresholds._();

  // ── Screen OFF (device asleep) ────────────────────────────────────
  /// A sleeping phone sits near 15-60 mA; sustained draw above this is a rogue wakelock.
  static const int sleepAnomalyMa = 280;

  /// Sleep draw that is unmistakably a runaway process.
  static const int sleepCriticalMa = 550;

  /// Sleep temperature that corroborates a runaway process.
  static const double sleepCriticalTempC = 38.0;

  /// Notification-worthy sleep draw.
  static const int sleepAlertMa = 450;

  // ── Screen ON (active use) ────────────────────────────────────────
  /// 120 Hz LTPO OLED panels legitimately pull 400-900 mA.
  static const int activeHeavyMa = 950;

  /// Active draw requiring thermal corroboration before it is called critical.
  static const int activeCriticalMa = 1400;

  /// Critical only when hot as well.
  static const double activeCriticalTempC = 40.0;

  /// Absolute active ceiling: critical regardless of temperature.
  static const int activeAbsoluteMa = 1600;

  /// Anomaly-engine entry point for active thermal runaway.
  static const int activeAnomalyMa = 1500;

  /// Thermal status at/above which a hot active spike is corroborated (MODERATE+).
  static const int thermalModerate = 2;

  // ── Incident dedupe ───────────────────────────────────────────────
  /// One sustained event produces one incident, not one per tick.
  static const Duration incidentCooldown = Duration(minutes: 5);

  /// Consecutive samples required before declaring a sustained anomaly.
  static const int consecutiveSpikeSamples = 2;

  // ── History noise floor ───────────────────────────────────────────
  /// A charge/discharge cycle shorter than this is a plug-in blip or a
  /// single-sample artefact, not a cycle. It must also move the battery >= 1%.
  static const Duration minSessionDuration = Duration(minutes: 2);

  /// Minimum battery movement for a charge/discharge session to be recorded.
  static const int minSessionDeltaPercent = 1;

  /// A standby interval shorter than this is just the screen being off while
  /// the phone is pocketed, not a sleep study.
  static const Duration minStandbyDuration = Duration(minutes: 10);

  /// The live "ACTIVE" card only appears once the in-progress session is long
  /// enough to mean something — otherwise every app launch flashes a card.
  static const Duration minLiveCardDuration = Duration(minutes: 1);
}
