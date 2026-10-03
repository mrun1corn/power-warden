package com.powerwarden.power_warden.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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

    private val powerConnectionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            // When user plugs or unplugs charger, immediately sample and broadcast to UI & notification!
            serviceScope.launch {
                val metrics = sampleMetrics()
                withContext(Dispatchers.Main) {
                    listener?.invoke(metrics)
                }
                updateSmartNotification(metrics)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        batteryProbe = BatteryProbe(this)
        thermalObserver = ThermalObserver(this) {}
        screenObserver = ScreenObserver(this) { _, _ -> }

        thermalObserver.start()
        screenObserver.start()
        createNotificationChannel()

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
            addAction(Intent.ACTION_BATTERY_CHANGED)
        }
        registerReceiver(powerConnectionReceiver, filter)
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

    private fun updateSmartNotification(metrics: Map<String, Any>) {
        val isCharging = (metrics["isCharging"] as? Boolean) ?: false
        val level = (metrics["batteryLevel"] as? Int) ?: 50
        val currentMa = (metrics["currentMa"] as? Int) ?: 0
        val absMa = Math.abs(currentMa)
        val temp = (metrics["temperatureCelsius"] as? Double) ?: 35.0
        val voltageMv = (metrics["voltageMv"] as? Int) ?: 4000
        val watts = String.format("%.1f", (voltageMv / 1000.0) * (absMa / 1000.0))
        val percentPerHour = String.format("%.1f", (absMa / 4500.0) * 100.0)

        val title: String
        val content: String

        if (isCharging) {
            title = "⚡ Charging: $level% · +$absMa mA (${watts}W)"
            content = "Temp: ${String.format("%.1f", temp)}°C · Fast charging healthy"
        } else if (currentDrainSpike(metrics)) {
            title = "⚠️ High Discharge: $level% · -$absMa mA ($percentPerHour%/hr)"
            content = "Heavy battery burn detected · Temp: ${String.format("%.1f", temp)}°C"
        } else {
            val hoursLeft = String.format("%.1f", level * 0.22)
            title = "🔋 $level% · -$absMa mA ($percentPerHour%/hr)"
            content = "About ${hoursLeft}h left · ${String.format("%.1f", temp)}°C · All calm"
        }

        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = openIntent?.let {
            android.app.PendingIntent.getActivity(
                this,
                1005,
                it,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) android.app.PendingIntent.FLAG_IMMUTABLE else 0
            )
        }

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_lock_idle_charging)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun currentDrainSpike(metrics: Map<String, Any>): Boolean {
        val isScreenOn = (metrics["isScreenOn"] as? Boolean) ?: true
        val currentMa = Math.abs((metrics["currentMa"] as? Int) ?: 0)
        return (!isScreenOn && currentMa > 300) || (isScreenOn && currentMa > 1200)
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

    private var lastNotificationUpdateMs = 0L

    private val tickerRunnable = Runnable {
        serviceScope.launch {
            val metrics = sampleMetrics()
            withContext(Dispatchers.Main) {
                listener?.invoke(metrics)
            }

            // Smart notification update: updates smoothly without waking device unnecessarily
            val now = System.currentTimeMillis()
            val isScreenOn = screenObserver.isInteractive()
            if (isScreenOn && (now - lastNotificationUpdateMs >= 4_000L)) {
                lastNotificationUpdateMs = now
                updateSmartNotification(metrics)
            } else if (!isScreenOn && (now - lastNotificationUpdateMs >= 60_000L)) {
                lastNotificationUpdateMs = now
                updateSmartNotification(metrics)
            }

            // Adaptive Zero-Wake interval calculation
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
        try {
            unregisterReceiver(powerConnectionReceiver)
        } catch (_: Exception) {}
        thermalObserver.stop()
        screenObserver.stop()
        serviceScope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
