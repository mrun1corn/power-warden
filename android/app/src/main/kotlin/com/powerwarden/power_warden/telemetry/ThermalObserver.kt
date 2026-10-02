package com.powerwarden.power_warden.telemetry

import android.content.Context
import android.os.Build
import android.os.PowerManager

/**
 * Monitors hardware thermal states and throttling via PowerManager.OnThermalStatusChangedListener (Android 10+ / API 29+).
 */
class ThermalObserver(
    private val context: Context,
    private val onStatusChanged: (Int) -> Unit
) {
    private val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private var thermalListener: PowerManager.OnThermalStatusChangedListener? = null

    var currentStatus: Int = 0
        private set

    fun start() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                currentStatus = powerManager.currentThermalStatus
                val listener = PowerManager.OnThermalStatusChangedListener { status ->
                    currentStatus = status
                    onStatusChanged(status)
                }
                powerManager.addThermalStatusListener(context.mainExecutor, listener)
                thermalListener = listener
            } catch (e: Exception) {
                currentStatus = 0
            }
        } else {
            currentStatus = 0
        }
    }

    fun stop() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            thermalListener?.let {
                try {
                    powerManager.removeThermalStatusListener(it)
                } catch (_: Exception) {}
                thermalListener = null
            }
        }
    }

    companion object {
        fun getStatusName(status: Int): String {
            return when (status) {
                0 -> "NONE"
                1 -> "LIGHT"
                2 -> "MODERATE"
                3 -> "SEVERE"
                4 -> "CRITICAL"
                5 -> "EMERGENCY"
                6 -> "SHUTDOWN"
                else -> "UNKNOWN ($status)"
            }
        }
    }
}
