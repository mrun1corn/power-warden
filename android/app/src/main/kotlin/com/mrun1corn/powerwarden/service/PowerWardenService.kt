package com.mrun1corn.powerwarden.service

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
import com.mrun1corn.powerwarden.telemetry.BatteryProbe
import com.mrun1corn.powerwarden.telemetry.ScreenObserver
import com.mrun1corn.powerwarden.telemetry.ThermalObserver
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
    private lateinit var anomalyDetector: AnomalyDetector

    private var isRunning = false
    private val handler = Handler(Looper.getMainLooper())

    companion object {
        const val CHANNEL_ID = "power_warden_sentinel"
        const val NOTIFICATION_ID = 8001
        const val ACTION_START = "com.mrun1corn.powerwarden.action.START"
        const val ACTION_STOP = "com.mrun1corn.powerwarden.action.STOP"

        /** Flush buffered telemetry after this many samples. */
        const val TELEMETRY_FLUSH_SAMPLES = 10

        /** …or after this long, whichever comes first. */
        const val TELEMETRY_FLUSH_INTERVAL_MS = 60_000L

        var listener: ((Map<String, Any>) -> Unit)? = null

        fun getDatabaseDir(context: Context): java.io.File {
            val dir = java.io.File(context.filesDir.parentFile, "app_flutter/power_warden_data")
            if (!dir.exists()) dir.mkdirs()
            return dir
        }
    }

    private val powerConnectionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            serviceScope.launch {
                val metrics = sampleMetrics()
                withContext(Dispatchers.Main) {
                    listener?.invoke(metrics)
                }
                updateSmartNotification(metrics)
            }
        }
    }

    // ── Native charge/discharge session tracking (survives UI closure) ──
    // The service owns session lifecycle so history is recorded even when
    // the Flutter UI is never opened. Screen on/off seconds are accumulated
    // per session for the standard screen-on vs deep-sleep drain split.
    private var sessionIsCharging: Boolean? = null
    private var sessionStartTimeMs: Long = 0L
    private var sessionStartLevel: Int = -1
    private var sessionStartTemp: Double = 0.0
    private var sessionPeakMa: Int = 0
    private var sessionPeakWatts: Double = 0.0
    private var sessionMinTemp: Double = Double.MAX_VALUE
    private var sessionMaxTemp: Double = Double.MIN_VALUE
    private var sessionScreenOnMs: Long = 0L
    private var sessionScreenOffMs: Long = 0L
    private var lastTickScreenOn: Boolean = true
    private var lastTickWallMs: Long = 0L

    private fun onChargingStateChanged(metrics: Map<String, Any>) {
        val nowCharging = (metrics["isCharging"] as? Boolean) ?: false
        val now = System.currentTimeMillis()

        if (sessionIsCharging == null) {
            // First observation after service start: adopt current state
            sessionIsCharging = nowCharging
            sessionStartTimeMs = now
            sessionStartLevel = (metrics["batteryLevel"] as? Int) ?: -1
            sessionStartTemp = (metrics["temperatureCelsius"] as? Double) ?: 0.0
            resetSessionExtremes(metrics)
            lastTickWallMs = now
            lastTickScreenOn = (metrics["isScreenOn"] as? Boolean) ?: true
            return
        }

        if (sessionIsCharging != nowCharging) {
            finalizeNativeSession(metrics, now)
            // Start the new session
            sessionIsCharging = nowCharging
            sessionStartTimeMs = now
            sessionStartLevel = (metrics["batteryLevel"] as? Int) ?: -1
            sessionStartTemp = (metrics["temperatureCelsius"] as? Double) ?: 0.0
            resetSessionExtremes(metrics)
            sessionScreenOnMs = 0L
            sessionScreenOffMs = 0L
            lastTickWallMs = now
            lastTickScreenOn = (metrics["isScreenOn"] as? Boolean) ?: true
        }
    }

    private fun resetSessionExtremes(metrics: Map<String, Any>) {
        val absMa = Math.abs((metrics["currentMa"] as? Int) ?: 0)
        val temp = (metrics["temperatureCelsius"] as? Double) ?: 30.0
        val voltageMv = (metrics["voltageMv"] as? Int) ?: 4000
        sessionPeakMa = absMa
        sessionPeakWatts = (voltageMv / 1000.0) * (absMa / 1000.0)
        sessionMinTemp = temp
        sessionMaxTemp = temp
    }

    /** Accumulates screen on/off time and peak stats on every telemetry tick. */
    private fun onTelemetryTick(metrics: Map<String, Any>) {
        if (sessionIsCharging == null) {
            onChargingStateChanged(metrics)
            return
        }
        val now = System.currentTimeMillis()
        val isScreenOn = (metrics["isScreenOn"] as? Boolean) ?: true
        val elapsed = if (lastTickWallMs > 0) (now - lastTickWallMs).coerceIn(0L, 120_000L) else 0L
        if (isScreenOn) sessionScreenOnMs += elapsed else sessionScreenOffMs += elapsed
        lastTickWallMs = now
        lastTickScreenOn = isScreenOn

        val absMa = Math.abs((metrics["currentMa"] as? Int) ?: 0)
        val temp = (metrics["temperatureCelsius"] as? Double) ?: 30.0
        val voltageMv = (metrics["voltageMv"] as? Int) ?: 4000
        if (absMa > sessionPeakMa) {
            sessionPeakMa = absMa
            sessionPeakWatts = (voltageMv / 1000.0) * (absMa / 1000.0)
        }
        if (temp < sessionMinTemp) sessionMinTemp = temp
        if (temp > sessionMaxTemp) sessionMaxTemp = temp
    }

    private fun finalizeNativeSession(metrics: Map<String, Any>, now: Long) {
        val durationMs = now - sessionStartTimeMs
        val endLevel = (metrics["batteryLevel"] as? Int) ?: sessionStartLevel
        val deltaPercent = Math.abs(endLevel - sessionStartLevel)

        // Persist only meaningful cycles: both a real duration AND real battery
        // movement. The old "45s OR 1%" gate let 45-second blips into history,
        // which is what made the History tab look like noise.
        val isMeaningful = durationMs >= DrainThresholds.MIN_SESSION_DURATION_MS &&
            deltaPercent >= DrainThresholds.MIN_SESSION_DELTA_PERCENT
        if (isMeaningful) {
            val capacityMah = batteryProbe.getCapacityMah()
            val mahDelta = Math.max(
                15,
                ((deltaPercent / 100.0) * capacityMah).toInt()
            )
            recordNativePowerSession(
                type = if (sessionIsCharging == true) "charging" else "discharging",
                startTime = sessionStartTimeMs,
                endTime = now,
                startLevel = sessionStartLevel,
                endLevel = endLevel,
                mahDelta = mahDelta,
                peakMa = sessionPeakMa,
                peakWatts = sessionPeakWatts,
                minTemp = sessionMinTemp,
                maxTemp = sessionMaxTemp,
                screenOnSeconds = (sessionScreenOnMs / 1000L).toInt(),
                screenOffSeconds = (sessionScreenOffMs / 1000L).toInt()
            )
        }
    }

    private var sleepStartTimeMs: Long = 0L
    private var sleepStartLevel: Int = 0
    private var sleepStartTemp: Double = 0.0

    override fun onCreate() {
        super.onCreate()
        batteryProbe = BatteryProbe(this)
        anomalyDetector = AnomalyDetector(this)
        thermalObserver = ThermalObserver(this) {}
        screenObserver = ScreenObserver(this) { isScreenOn, sleepDurationMs ->
            // Native Standby Sleep Session Persistence
            if (!isScreenOn) {
                // Phone just went to sleep
                sleepStartTimeMs = System.currentTimeMillis()
                val snap = batteryProbe.readInstantaneousSample()
                sleepStartLevel = snap.batteryLevel
                sleepStartTemp = snap.temperatureCelsius
            } else if (sleepDurationMs >= DrainThresholds.MIN_STANDBY_DURATION_MS &&
                sleepStartTimeMs > 0L
            ) {
                // Phone woke up after a real rest (>= 10 min). Shorter screen-off
                // gaps are pocket time, not standby sleep, and used to flood the
                // Standby tab with 1-minute "sleep" entries.
                val wakeTime = System.currentTimeMillis()
                val snap = batteryProbe.readInstantaneousSample()
                val deltaLevel = Math.abs(snap.batteryLevel - sleepStartLevel)
                val mahDelta = Math.max(10, ((deltaLevel / 100.0) * batteryProbe.getCapacityMah()).toInt())

                recordNativePowerSession(
                    type = "standby",
                    startTime = sleepStartTimeMs,
                    endTime = wakeTime,
                    startLevel = sleepStartLevel,
                    endLevel = snap.batteryLevel,
                    mahDelta = mahDelta,
                    peakMa = Math.abs(snap.currentMilliamps),
                    peakWatts = (snap.voltageMillivolts / 1000.0) * (Math.abs(snap.currentMilliamps) / 1000.0),
                    minTemp = Math.min(sleepStartTemp, snap.temperatureCelsius),
                    maxTemp = Math.max(sleepStartTemp, snap.temperatureCelsius)
                )
                sleepStartTimeMs = 0L
            }
        }

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

    private fun recordNativePowerSession(
        type: String,
        startTime: Long,
        endTime: Long,
        startLevel: Int,
        endLevel: Int,
        mahDelta: Int,
        peakMa: Int,
        peakWatts: Double,
        minTemp: Double,
        maxTemp: Double,
        screenOnSeconds: Int = 0,
        screenOffSeconds: Int = ((endTime - startTime) / 1000).toInt(),
    ) {
        recordNativePowerSession(
            NativeSession(
                type, startTime, endTime, startLevel, endLevel,
                mahDelta, peakMa, peakWatts, minTemp, maxTemp,
                screenOnSeconds, screenOffSeconds,
            )
        )
    }

    /** Bundles a completed session's fields (keeps call sites readable). */
    private data class NativeSession(
        val type: String,
        val startTime: Long,
        val endTime: Long,
        val startLevel: Int,
        val endLevel: Int,
        val mahDelta: Int,
        val peakMa: Int,
        val peakWatts: Double,
        val minTemp: Double,
        val maxTemp: Double,
        val screenOnSeconds: Int,
        val screenOffSeconds: Int,
    )

    private fun recordNativePowerSession(s: NativeSession) {
        serviceScope.launch(Dispatchers.IO) {
            try {
                val dbDir = getDatabaseDir(applicationContext)
                val file = java.io.File(dbDir, "power_sessions.jsonl")
                val json = org.json.JSONObject().apply {
                    put("id", s.startTime.toString())
                    put("type", s.type)
                    put("startTime", s.startTime)
                    put("endTime", s.endTime)
                    put("startBatteryLevel", s.startLevel)
                    put("endBatteryLevel", s.endLevel)
                    put("totalMahDelta", s.mahDelta)
                    put("peakMa", s.peakMa)
                    put("peakWatts", s.peakWatts)
                    put("minTempCelsius", s.minTemp)
                    put("maxTempCelsius", s.maxTemp)
                    put("screenOnSeconds", s.screenOnSeconds)
                    put("screenOffSeconds", s.screenOffSeconds)
                    put("topAppName", "")
                }
                file.appendText(json.toString() + "\n")
            } catch (_: Exception) { /* best-effort; failure is non-fatal */ }
        }
    }

    /**
     * Batched telemetry writer.
     *
     * The foreground service is the ONLY writer of `telemetry_samples.jsonl`
     * (the Flutter layer used to append the same samples a second time).
     * Writes are buffered so a 2 s screen-on tick does not mean a flash write
     * every 2 s: flush at 10 samples, or every 60 s, whichever comes first.
     */
    private val telemetryBuffer = ArrayDeque<String>()
    private var lastTelemetryFlushMs = 0L

    private fun logNativeTelemetrySample(metrics: Map<String, Any>) {
        val json = org.json.JSONObject().apply {
            put("timestamp", metrics["timestamp"] ?: System.currentTimeMillis())
            put("batteryLevel", metrics["batteryLevel"] ?: 50)
            put("currentMilliamps", metrics["currentMa"] ?: 0)
            put("temperatureCelsius", metrics["temperatureCelsius"] ?: 30.0)
            put("thermalStatus", metrics["thermalStatus"] ?: 0)
            put("isScreenOn", metrics["isScreenOn"] ?: true)
            put("isCharging", metrics["isCharging"] ?: false)
            put("voltageMv", metrics["voltageMv"] ?: 4000)
            put("sleepDurationMs", metrics["sleepDurationMs"] ?: 0)
            put("refreshRate", metrics["refreshRate"] ?: 60.0)
        }
        telemetryBuffer.addLast(json.toString())

        val now = System.currentTimeMillis()
        val due = telemetryBuffer.size >= TELEMETRY_FLUSH_SAMPLES ||
            now - lastTelemetryFlushMs >= TELEMETRY_FLUSH_INTERVAL_MS
        if (due) flushTelemetryBuffer(now)
    }

    private fun flushTelemetryBuffer(now: Long = System.currentTimeMillis()) {
        if (telemetryBuffer.isEmpty()) return
        val payload = telemetryBuffer.joinToString(separator = "\n", postfix = "\n")
        telemetryBuffer.clear()
        lastTelemetryFlushMs = now
        serviceScope.launch(Dispatchers.IO) {
            try {
                java.io.File(getDatabaseDir(applicationContext), "telemetry_samples.jsonl")
                    .appendText(payload)
            } catch (_: Exception) { /* best-effort; failure is non-fatal */ }
        }
    }

    /** Synchronous variant for shutdown, when the coroutine scope is about to die. */
    private fun flushTelemetryBufferBlocking() {
        if (telemetryBuffer.isEmpty()) return
        val payload = telemetryBuffer.joinToString(separator = "\n", postfix = "\n")
        telemetryBuffer.clear()
        lastTelemetryFlushMs = System.currentTimeMillis()
        try {
            java.io.File(getDatabaseDir(applicationContext), "telemetry_samples.jsonl")
                .appendText(payload)
        } catch (_: Exception) { /* best-effort; failure is non-fatal */ }
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

    private var smoothedMaEwma: Double = 0.0

    private fun updateSmartNotification(metrics: Map<String, Any>) {
        val isCharging = (metrics["isCharging"] as? Boolean) ?: false
        val level = (metrics["batteryLevel"] as? Int) ?: 50
        val currentMa = (metrics["currentMa"] as? Int) ?: 0
        val absMa = Math.abs(currentMa)

        // Exponential Moving Average filter (alpha = 0.25) to smooth out instant 1-sample spikes in notification
        if (smoothedMaEwma == 0.0) {
            smoothedMaEwma = absMa.toDouble()
        } else {
            smoothedMaEwma = (0.25 * absMa) + (0.75 * smoothedMaEwma)
        }
        val displayMa = Math.round(smoothedMaEwma).toInt()

        val temp = (metrics["temperatureCelsius"] as? Double) ?: 35.0
        val voltageMv = (metrics["voltageMv"] as? Int) ?: 4000
        val watts = String.format("%.1f", (voltageMv / 1000.0) * (displayMa / 1000.0))
        val capacityMah = batteryProbe.getCapacityMah()
        val percentPerHour = String.format("%.1f", (displayMa.toDouble() / capacityMah) * 100.0)

        val title: String
        val content: String

        if (isCharging) {
            title = "⚡ Charging: $level% · +$displayMa mA (${watts}W)"
            content = "Temp: ${String.format("%.1f", temp)}°C · Fast charging healthy"
        } else if (currentDrainSpike(metrics)) {
            title = "⚠️ High Discharge: $level% · -$displayMa mA ($percentPerHour%/hr)"
            content = "Heavy battery burn detected · Temp: ${String.format("%.1f", temp)}°C"
        } else {
            // Dynamic hours left calculation based on live current
            val activeMa = Math.max(150, displayMa)
            val nominalCapacityMah = capacityMah.toDouble()
            val remainingMah = (level / 100.0) * nominalCapacityMah
            val hoursLeft = String.format("%.1f", remainingMah / activeMa)
            title = "🔋 $level% · -$displayMa mA ($percentPerHour%/hr)"
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
        val temp = (metrics["temperatureCelsius"] as? Double) ?: 30.0
        // Thresholds come from DrainThresholds so the notification, the anomaly
        // engine, and the dashboard badge can never disagree about one sample.
        return (!isScreenOn && currentMa > DrainThresholds.SLEEP_ALERT_MA) ||
            (isScreenOn &&
                currentMa > DrainThresholds.ACTIVE_ABSOLUTE_MA &&
                temp >= DrainThresholds.ACTIVE_CRITICAL_TEMP_C)
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
            logNativeTelemetrySample(metrics)

            // Native session lifecycle: track charge/discharge even with UI closed
            onTelemetryTick(metrics)
            // Detect plug/unplug transitions immediately (also handled on tick)
            onChargingStateChanged(metrics)

            // Runaway-drain detection lives here, not in the Flutter UI, so it
            // keeps working when the Activity is gone.
            anomalyDetector.closeIfSettled(metrics)?.let { closed ->
                anomalyDetector.persistClosure(closed)
            }
            anomalyDetector.evaluate(metrics)?.let { opened ->
                anomalyDetector.persist(opened)
                anomalyDetector.alertIfWarranted(opened)
            }

            withContext(Dispatchers.Main) {
                listener?.invoke(metrics)
            }

            // Smart notification update: updates smoothly without waking device unnecessarily
            val now = System.currentTimeMillis()
            val isScreenOn = screenObserver.isInteractive()
            // Throttled smart-notification refresh: 4s while awake, 60s asleep.
            val notificationIntervalMs = if (isScreenOn) {
                DrainThresholds.NOTIFICATION_AWAKE_MS
            } else {
                DrainThresholds.NOTIFICATION_ASLEEP_MS
            }
            if (now - lastNotificationUpdateMs >= notificationIntervalMs) {
                lastNotificationUpdateMs = now
                updateSmartNotification(metrics)
            }

            // Adaptive Zero-Wake interval calculation
            val currentDrain = (metrics["currentMa"] as? Int) ?: 0

            val nextIntervalMs = when {
                isScreenOn -> DrainThresholds.TICK_SCREEN_ON_MS
                currentDrain > DrainThresholds.SLEEP_ANOMALY_MA ->
                    DrainThresholds.TICK_DRAIN_SPIKE_MS
                else -> DrainThresholds.TICK_SLEEP_MS
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
        val snap = batteryProbe.sampleFilteredMetrics()
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
            "refreshRate" to screenObserver.getActiveRefreshRate(),
            "sleepDurationMs" to screenObserver.getCurrentSleepDurationMs()
        )
    }

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacks(tickerRunnable)
        // Persist any buffered samples before the scope dies, otherwise up to a
        // minute of telemetry is lost every time the service stops.
        flushTelemetryBufferBlocking()
        try {
            unregisterReceiver(powerConnectionReceiver)
        } catch (_: Exception) { /* best-effort; failure is non-fatal */ }
        thermalObserver.stop()
        screenObserver.stop()
        serviceScope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
