package com.mrun1corn.powerwarden.telemetry

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
        val chargeCounterUah: Long = 0L, // Remaining charge in µAh (0 if unsupported)
        val timestampEpochMs: Long = System.currentTimeMillis()
    )

    /**
     * Estimated design capacity in mAh, derived from CHARGE_COUNTER (µAh) at a known
     * SOC level. Calibrated lazily: the first valid (counter, level) pair observed
     * at a level >= 50% is used to extrapolate full capacity. Falls back to a
     * conservative 4500 mAh when the kernel does not report charge counter.
     */
    @Volatile
    private var calibratedCapacityMah: Int = 0

    fun getCapacityMah(): Int {
        if (calibratedCapacityMah > 0) return calibratedCapacityMah
        try {
            val uah = batteryManager.getLongProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)
            if (uah > 0) {
                val level = getCurrentLevelPercent()
                if (level >= 50) {
                    val estimated = ((uah * 100.0) / level / 1000.0).toInt()
                    // Sanity bounds: real phone batteries are 2000–11000 mAh
                    if (estimated in 2000..11000) {
                        calibratedCapacityMah = estimated
                        return estimated
                    }
                }
            }
        } catch (_: Exception) {}
        return 4500
    }

    /**
     * Reads battery metrics with a 3-point rolling median filter to suppress transient 100-300ms
     * cellular/Wi-Fi transmission spikes.
     */
    fun sampleFilteredMetrics(): BatterySnapshot {
        val sample = readInstantaneousSample()
        recentCurrentSamples.add(sample.currentMilliamps)
        if (recentCurrentSamples.size > 3) {
            recentCurrentSamples.removeAt(0)
        }

        val sorted = recentCurrentSamples.sorted()
        val medianMa = if (sorted.size >= 3) sorted[1] else sample.currentMilliamps

        return sample.copy(currentMilliamps = medianMa)
    }

    private val recentCurrentSamples = mutableListOf<Int>()

    /**
     * Reads a single instantaneous snapshot from BatteryManager, sticky ACTION_BATTERY_CHANGED intent,
     * and direct Linux sysfs power supply nodes as OEM fallback (HyperOS/MIUI/Samsung).
     */
    fun readInstantaneousSample(): BatterySnapshot {
        val stickyIntent = context.registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        )

        // Read raw CURRENT_NOW (Long) with direct kernel sysfs fallback
        var rawCurrent = batteryManager.getLongProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
        if (rawCurrent == 0L || rawCurrent == Long.MIN_VALUE || rawCurrent == Long.MAX_VALUE) {
            rawCurrent = readSysfsBatteryCurrent()
        }

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

        // Charge counter (µAh) — remaining charge; used for capacity calibration
        val chargeCounterUah = try {
            batteryManager.getLongProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)
        } catch (_: Exception) { 0L }

        return BatterySnapshot(
            currentMilliamps = normalizedMa,
            rawCurrent = rawCurrent,
            temperatureCelsius = tempCelsius,
            voltageMillivolts = voltageMv,
            batteryLevel = level,
            isCharging = isCharging,
            chargeCounterUah = if (chargeCounterUah > 0) chargeCounterUah else 0L
        )
    }

    /** Current SOC percentage 0-100, or -1 when unavailable. */
    private fun getCurrentLevelPercent(): Int {
        val stickyIntent = context.registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        )
        return stickyIntent?.let {
            val cur = it.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = it.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            if (cur >= 0 && scale > 0) (cur * 100) / scale else -1
        } ?: batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
    }

    /**
     * Direct Linux Kernel sysfs nodes for Xiaomi/HyperOS/Redmi/Samsung/OnePlus.
     * Bypasses OEM framework sleeping layers.
     */
    private fun readSysfsBatteryCurrent(): Long {
        val paths = listOf(
            "/sys/class/power_supply/battery/current_now",
            "/sys/class/power_supply/bms/current_now",
            "/sys/class/power_supply/battery/batt_current",
            "/sys/class/power_supply/battery/current_avg",
            "/sys/class/power_supply/qcom-battery/current_now"
        )
        for (path in paths) {
            try {
                val file = java.io.File(path)
                if (file.exists() && file.canRead()) {
                    val line = file.readText().trim()
                    val value = line.toLongOrNull()
                    if (value != null && value != 0L) {
                        return value
                    }
                }
            } catch (_: Exception) {}
        }
        return 0L
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
        // If raw current itself was negative and not in charging state, or isCharging is explicitly true
        return if (isCharging || raw < 0L && scaledMa > 50.0 && !isRawDischarging(raw)) {
            -roundedMa
        } else {
            roundedMa
        }
    }

    private fun isRawDischarging(raw: Long): Boolean {
        // Some kernels report discharging as negative (e.g. -350 mA) and charging as positive.
        // We cross-check with charging status in readInstantaneousSample.
        return false
    }
}
