package com.powerwarden.power_warden.telemetry

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.SystemClock
import kotlin.math.abs

/**
 * High-precision battery sensor probe.
 * Handles OEM unit scaling (uA vs mA), sign polarity inversion, and cellular burst filtering.
 */
class BatteryProbe(private val context: Context) {

    private val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager

    data class BatterySnapshot(
        val currentMilliamps: Int,       // Positive = discharge (drain), Negative = charging
        val rawCurrent: Long,
        val temperatureCelsius: Double,
        val voltageMillivolts: Int,
        val batteryLevel: Int,
        val isCharging: Boolean,
        val timestampEpochMs: Long = System.currentTimeMillis()
    )

    /**
     * Reads battery metrics with a 3-point rolling median filter to suppress transient 100-300ms
     * cellular/Wi-Fi transmission spikes.
     */
    fun sampleFilteredMetrics(): BatterySnapshot {
        val sample1 = readInstantaneousSample()
        SystemClock.sleep(100)
        val sample2 = readInstantaneousSample()
        SystemClock.sleep(100)
        val sample3 = readInstantaneousSample()

        val sortedCurrents = listOf(sample1.currentMilliamps, sample2.currentMilliamps, sample3.currentMilliamps).sorted()
        val medianCurrent = sortedCurrents[1]

        // Use latest snapshot metadata with median current
        return sample3.copy(currentMilliamps = medianCurrent)
    }

    /**
     * Reads a single instantaneous snapshot from BatteryManager and sticky ACTION_BATTERY_CHANGED intent.
     */
    fun readInstantaneousSample(): BatterySnapshot {
        val stickyIntent = context.registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        )

        // Read raw CURRENT_NOW (Long)
        val rawCurrent = batteryManager.getLongProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)

        // Status & Charging state
        val status = stickyIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL

        // Level (0 - 100)
        val level = stickyIntent?.let {
            val cur = it.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = it.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            if (cur >= 0 && scale > 0) (cur * 100) / scale else -1
        } ?: batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)

        // Voltage in millivolts
        val voltageMv = stickyIntent?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, 0) ?: 0

        // Temperature in tenths of Celsius (e.g. 385 -> 38.5 C)
        val rawTemp = stickyIntent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
        val tempCelsius = rawTemp / 10.0

        // Normalize current
        val normalizedMa = normalizeCurrent(rawCurrent, isCharging)

        return BatterySnapshot(
            currentMilliamps = normalizedMa,
            rawCurrent = rawCurrent,
            temperatureCelsius = tempCelsius,
            voltageMillivolts = voltageMv,
            batteryLevel = level,
            isCharging = isCharging
        )
    }

    /**
     * Normalizes raw current:
     * 1. Scaling: Detects if OEM reports microamperes (uA) or milliamperes (mA).
     *    Standard AOSP is uA (e.g. 350,000 uA = 350 mA).
     *    Samsung/Realme/Huawei often report mA directly (e.g. 350).
     *    If |raw| >= 10,000 -> divide by 1000.
     * 2. Sign Convention:
     *    Standardized so Positive = Discharging (Drain rate in mA), Negative = Charging.
     */
    fun normalizeCurrent(raw: Long, isCharging: Boolean): Int {
        if (raw == 0L || raw == Long.MIN_VALUE || raw == Long.MAX_VALUE) {
            return 0
        }

        val absVal = abs(raw)
        val scaledMa = if (absVal >= 10_000L) {
            absVal / 1000.0
        } else {
            absVal.toDouble()
        }

        val roundedMa = Math.round(scaledMa).toInt()

        // Enforce consistent polarity: Positive = Draining, Negative = Charging
        return if (isCharging) {
            -roundedMa
        } else {
            roundedMa
        }
    }
}
