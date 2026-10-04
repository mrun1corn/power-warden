package com.powerwarden.power_warden.telemetry

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.PowerManager
import android.os.SystemClock

/**
 * Tracks device display state (Screen ON / OFF) and maintains monotonic sleep epoch duration.
 */
class ScreenObserver(
    private val context: Context,
    private val onStateChanged: (isScreenOn: Boolean, sleepDurationMs: Long) -> Unit
) {
    private val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager

    var isScreenOn: Boolean = powerManager.isInteractive
        private set

    private var screenOffTimestampMs: Long = if (!isScreenOn) SystemClock.elapsedRealtime() else 0L
    var lastSleepDurationMs: Long = 0L
        private set

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_ON -> {
                    val sleepDuration = if (screenOffTimestampMs > 0L) {
                        SystemClock.elapsedRealtime() - screenOffTimestampMs
                    } else 0L
                    isScreenOn = true
                    if (sleepDuration > 0L) {
                        lastSleepDurationMs = sleepDuration
                    }
                    screenOffTimestampMs = 0L
                    onStateChanged(true, sleepDuration)
                }
                Intent.ACTION_SCREEN_OFF -> {
                    isScreenOn = false
                    screenOffTimestampMs = SystemClock.elapsedRealtime()
                    onStateChanged(false, 0L)
                }
            }
        }
    }

    fun start() {
        isScreenOn = powerManager.isInteractive
        if (!isScreenOn) {
            screenOffTimestampMs = SystemClock.elapsedRealtime()
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        context.registerReceiver(receiver, filter)
    }

    fun stop() {
        try {
            context.unregisterReceiver(receiver)
        } catch (_: Exception) {}
    }

    /**
     * If currently screen-off, returns ongoing sleep ms.
     * If screen is on, returns the duration of the sleep cycle that just ended.
     */
    fun getCurrentSleepDurationMs(): Long {
        return if (!isScreenOn && screenOffTimestampMs > 0L) {
            SystemClock.elapsedRealtime() - screenOffTimestampMs
        } else {
            lastSleepDurationMs
        }
    }
}
