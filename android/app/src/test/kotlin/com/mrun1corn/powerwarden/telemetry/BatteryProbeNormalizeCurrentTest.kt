package com.mrun1corn.powerwarden.telemetry

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Contract tests for [BatteryProbe.normalizeCurrent].
 *
 * The app-wide invariant is: **positive mA = discharging, negative = charging**.
 * `AnomalyEngine` and `AnomalyDetector` compare these signed values against
 * drain thresholds, so any regression here silently disables all anomaly
 * detection — which is exactly the bug these tests lock down.
 */
class BatteryProbeNormalizeCurrentTest {

    @Test
    fun `aosp negative microamps while discharging becomes positive mA`() {
        // AOSP convention: -350000 uA means "drawing 350 mA".
        assertEquals(350, BatteryProbe.normalizeCurrent(-350_000L, isCharging = false))
    }

    @Test
    fun `aosp negative microamps while charging becomes negative mA`() {
        assertEquals(-1_500, BatteryProbe.normalizeCurrent(-1_500_000L, isCharging = true))
    }

    @Test
    fun `oem positive milliamps while discharging stays positive`() {
        // Samsung/Realme report mA directly with a positive magnitude.
        assertEquals(420, BatteryProbe.normalizeCurrent(420L, isCharging = false))
    }

    @Test
    fun `positive raw while charging is still reported as negative`() {
        // Some kernels report a positive magnitude even while charging.
        assertEquals(-2_100, BatteryProbe.normalizeCurrent(2_100L, isCharging = true))
    }

    @Test
    fun `microamp scale boundary is handled`() {
        assertEquals(10, BatteryProbe.normalizeCurrent(10_000L, isCharging = false))
        // Just under the uA threshold is treated as mA.
        assertEquals(9_999, BatteryProbe.normalizeCurrent(9_999L, isCharging = false))
    }

    @Test
    fun `sensor sentinel values become zero`() {
        assertEquals(0, BatteryProbe.normalizeCurrent(0L, isCharging = false))
        assertEquals(0, BatteryProbe.normalizeCurrent(Long.MIN_VALUE, isCharging = false))
        assertEquals(0, BatteryProbe.normalizeCurrent(Long.MAX_VALUE, isCharging = false))
    }

    @Test
    fun `implausible readings are clamped instead of poisoning the UI`() {
        assertEquals(
            BatteryProbe.MAX_PLAUSIBLE_MA,
            BatteryProbe.normalizeCurrent(900_000_000L, isCharging = false),
        )
    }

    @Test
    fun `sleep drain thresholds are reachable from normalized output`() {
        // 600 mA asleep must land above the anomaly threshold as a positive int.
        val normalized = BatteryProbe.normalizeCurrent(-600_000L, isCharging = false)
        assertEquals(600, normalized)
        assert(normalized > 280) { "engine would miss this sample" }
    }
}
