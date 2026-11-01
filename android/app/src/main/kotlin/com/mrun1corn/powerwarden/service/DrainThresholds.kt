package com.mrun1corn.powerwarden.service

/**
 * Single source of truth for every drain threshold in PowerWarden.
 *
 * Every layer (foreground service, anomaly engine, notification copy) reads
 * from here so the app cannot contradict itself about the same physical event.
 * The Dart mirror lives in `lib/domain/drain_thresholds.dart` — keep both in
 * sync; both are asserted by tests.
 *
 * Current values are signed: **positive mA = discharge**, negative = charging.
 */
object DrainThresholds {

    // ── Screen OFF (device asleep) ────────────────────────────────────
    /** A sleeping phone should sit near 15-60 mA. Sustained draw above this is a rogue wakelock. */
    const val SLEEP_ANOMALY_MA = 280

    /** Sleep draw that is unmistakably a runaway process rather than a routine sync. */
    const val SLEEP_CRITICAL_MA = 550

    /** Sleep temperature that corroborates a runaway process. */
    const val SLEEP_CRITICAL_TEMP_C = 38.0

    /** Notification-worthy sleep draw. */
    const val SLEEP_ALERT_MA = 450

    // ── Screen ON (active use) ────────────────────────────────────────
    /** 120 Hz LTPO OLED panels legitimately pull 400-900 mA. */
    const val ACTIVE_HEAVY_MA = 950

    /** Active draw requiring thermal corroboration before it is called critical. */
    const val ACTIVE_CRITICAL_MA = 1400

    /** Critical only when hot as well — avoids alarming users mid-game. */
    const val ACTIVE_CRITICAL_TEMP_C = 40.0

    /** Absolute active ceiling: critical regardless of temperature. */
    const val ACTIVE_ABSOLUTE_MA = 1600

    /** Anomaly-engine entry point for active thermal runaway. */
    const val ACTIVE_ANOMALY_MA = 1500

    /** Thermal status at/above which a hot active spike is corroborated (MODERATE+). */
    const val THERMAL_MODERATE = 2

    // ── Sampling cadence ──────────────────────────────────────────────
    /** Screen on: fast enough to feel live, cheap enough to ignore. */
    const val TICK_SCREEN_ON_MS = 2_000L

    /** Screen off with an active drain spike: keep watching closely. */
    const val TICK_DRAIN_SPIKE_MS = 30_000L

    /** Screen off and calm: relax to protect deep sleep. */
    const val TICK_SLEEP_MS = 60_000L

    /** Notification refresh while the user is looking at the device. */
    const val NOTIFICATION_AWAKE_MS = 4_000L

    /** Notification refresh while asleep — one per minute is plenty. */
    const val NOTIFICATION_ASLEEP_MS = 60_000L

    // ── Incident dedupe ───────────────────────────────────────────────
    /** One sustained event must produce one incident, not one per tick. */
    const val INCIDENT_COOLDOWN_MS = 5 * 60 * 1000L

    /** Consecutive samples required before declaring a sustained anomaly. */
    const val CONSECUTIVE_SPIKE_SAMPLES = 2

    // ── History noise floor ───────────────────────────────────────────
    /**
     * A charge/discharge cycle shorter than this is not a cycle — it is a
     * plug-in blip, a single-sample artefact, or the tail of a previous
     * session. Sessions must ALSO move the battery by >= 1%.
     */
    const val MIN_SESSION_DURATION_MS = 2 * 60 * 1000L

    /** Minimum battery movement for a charge/discharge session to be recorded. */
    const val MIN_SESSION_DELTA_PERCENT = 1

    /**
     * A standby interval shorter than this is just the screen being off while
     * the user pockets the phone, not a sleep study.
     */
    const val MIN_STANDBY_DURATION_MS = 10 * 60 * 1000L
}
