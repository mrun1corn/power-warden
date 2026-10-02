package com.powerwarden.power_warden.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import com.powerwarden.power_warden.telemetry.BatteryProbe
import com.powerwarden.power_warden.telemetry.ScreenObserver
import com.powerwarden.power_warden.telemetry.ThermalObserver
import kotlinx.coroutines.*

/**
 * Low-overhead foreground service for silent battery drain detection.
 * Compliant with Android 14/15 specialUse foreground service restrictions.
 */
class PowerWardenService : Service() {

    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private lateinit var batteryProbe: BatteryProbe
    private lateinit var thermalObserver: ThermalObserver
    private lateinit var screenObserver: ScreenObserver

    private var isRunning = false
    private val handler = Handler(Looper.getMainLooper())

    companion object {
        const val CHANNEL_ID = "power_warden_sentinel"
        const val NOTIFICATION_ID = 8001
        const val ACTION_START = "com.powerwarden.action.START"
        const val ACTION_STOP = "com.powerwarden.action.STOP"

        var listener: ((Map<String, Any>) -> Unit)? = null
    }

    override fun onCreate() {
        super.onCreate()
        batteryProbe = BatteryProbe(this)
        thermalObserver = ThermalObserver(this) {}
        screenObserver = ScreenObserver(this) { _, _ -> }

        thermalObserver.start()
        screenObserver.start()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                startForegroundWithNotification()
                if (!isRunning) {
                    isRunning = true
                    scheduleNextTick(0L)
                }
            }
        }
        return START_STICKY
    }

    private fun startForegroundWithNotification() {
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("PowerWarden Active")
            .setContentText("Monitoring battery drain and system anomalies")
            .setSmallIcon(android.R.drawable.ic_lock_idle_charging)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "PowerWarden Sentinel",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Silent foreground monitoring of power drain"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private val tickerRunnable = Runnable {
        serviceScope.launch {
            val metrics = sampleMetrics()
            withContext(Dispatchers.Main) {
                listener?.invoke(metrics)
            }

            // Adaptive Zero-Wake interval calculation
            val isScreenOn = screenObserver.isInteractive()
            val currentDrain = (metrics["currentMa"] as? Int) ?: 0

            val nextIntervalMs = when {
                isScreenOn -> 2_000L // Fast updates when screen is active
                currentDrain > 350 -> 30_000L // Tighten loop on drain spike
                else -> 60_000L // Calm idle: relaxed to protect deep sleep
            }

            if (isRunning) {
                scheduleNextTick(nextIntervalMs)
            }
        }
    }

    private fun scheduleNextTick(delayMs: Long) {
        handler.postDelayed(tickerRunnable, delayMs)
    }

    private fun ScreenObserver.isInteractive(): Boolean = this.isScreenOn

    private fun sampleMetrics(): Map<String, Any> {
        val snap = batteryProbe.readInstantaneousSample()
        return mapOf(
            "timestamp" to snap.timestampEpochMs,
            "currentMa" to snap.currentMilliamps,
            "rawCurrent" to snap.rawCurrent,
            "temperatureCelsius" to snap.temperatureCelsius,
            "voltageMv" to snap.voltageMillivolts,
            "batteryLevel" to snap.batteryLevel,
            "isCharging" to snap.isCharging,
            "thermalStatus" to thermalObserver.currentStatus,
            "isScreenOn" to screenObserver.isScreenOn,
            "sleepDurationMs" to screenObserver.getCurrentSleepDurationMs()
        )
    }

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacks(tickerRunnable)
        thermalObserver.stop()
        screenObserver.stop()
        serviceScope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
