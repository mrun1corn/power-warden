package com.mrun1corn.powerwarden.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.io.File

/**
 * Native runaway-drain detector.
 *
 * This used to live in `DashboardScreen`, which meant analysis, dedupe state and
 * incident persistence all died with the Activity — the foreground service kept
 * sampling into the void. It now runs inside [PowerWardenService], so detection,
 * logging and alerting continue while the UI is closed or the process is killed.
 *
 * Responsibilities:
 *  - evaluate each sample against [DrainThresholds]
 *  - keep ONE incident per sustained event (dedupe + close-on-settle)
 *  - append incidents to `anomaly_incidents.jsonl` for the Sentinel log
 *  - raise a notification only for critical events, rate-limited
 */
class AnomalyDetector(private val context: Context) {

    /** A completed or in-flight drain event. Mirrors Dart's `AnomalyIncident`. */
    data class Incident(
        val startTime: Long,
        val endTime: Long? = null,
        val severity: Severity,
        val peakCurrentMa: Int,
        val maxTemperatureCelsius: Double,
        val culpritPackage: String? = null,
        val culpritThread: String? = null,
        val diagnosis: String,
        val recommendedAction: String? = null,
        val isRemediated: Boolean = false,
    ) {
        fun toJson(): JSONObject = JSONObject().apply {
            put("startTime", startTime)
            put("endTime", endTime ?: JSONObject.NULL)
            put("severity", severity.wire)
            put("peakCurrentMa", peakCurrentMa)
            put("maxTemperatureCelsius", maxTemperatureCelsius)
            put("culpritPackage", culpritPackage ?: JSONObject.NULL)
            put("culpritThread", culpritThread ?: JSONObject.NULL)
            put("diagnosis", diagnosis)
            put("recommendedAction", recommendedAction ?: JSONObject.NULL)
            put("isRemediated", isRemediated)
        }
    }

    enum class Severity(val wire: String) {
        MILD("mild"),
        MODERATE("moderate"),
        CRITICAL("critical"),
    }

    // ── Rolling window (screen-off needs two consecutive spiking samples) ──
    private val recent = ArrayDeque<Snapshot>()
    private var lastSleepIncident: Incident? = null
    private var lastActiveIncident: Incident? = null

    // ── Alert rate limiting (mirrors NotificationService's policy) ──
    private var lastAlertAt = 0L
    private val recentAlerts = ArrayDeque<Long>()
    private val alertCooldownMs = 15 * 60 * 1000L
    private val maxAlertsPerHour = 3

    private data class Snapshot(
        val timestamp: Long,
        val currentMa: Int,
        val tempC: Double,
        val isScreenOn: Boolean,
        val isCharging: Boolean,
    )

    /**
     * Evaluates one telemetry tick.
     *
     * @return the incident to persist if this tick *opened* one, else null.
     *         Incidents that were merely extended are persisted by [closeIfSettled]
     *         or already written when they opened.
     */
    fun evaluate(metrics: Map<String, Any>): Incident? {
        val snapshot = Snapshot(
            timestamp = (metrics["timestamp"] as? Long) ?: System.currentTimeMillis(),
            currentMa = (metrics["currentMa"] as? Int) ?: 0,
            tempC = (metrics["temperatureCelsius"] as? Double) ?: 0.0,
            isScreenOn = (metrics["isScreenOn"] as? Boolean) ?: true,
            isCharging = (metrics["isCharging"] as? Boolean) ?: false,
        )

        if (snapshot.isCharging) {
            recent.clear()
            return null
        }

        recent.addLast(snapshot)
        while (recent.size > 15) recent.removeFirst()

        if (!snapshot.isScreenOn) {
            return evaluateSleep(snapshot)
        }
        return evaluateActive(snapshot)
    }

    // ── Screen OFF: the headline feature ──────────────────────────────
    private fun evaluateSleep(snapshot: Snapshot): Incident? {
        if (recent.size < DrainThresholds.CONSECUTIVE_SPIKE_SAMPLES) return null

        val window = recent.toList().takeLast(DrainThresholds.CONSECUTIVE_SPIKE_SAMPLES)
        val allSpiking = window.all {
            !it.isScreenOn && it.currentMa >= DrainThresholds.SLEEP_ANOMALY_MA
        }
        if (!allSpiking) return null

        val peakMa = window.maxOf { it.currentMa }
        val maxTemp = window.maxOf { it.tempC }

        // Same ongoing event? Extend silently instead of logging a duplicate.
        val previous = lastSleepIncident
        if (previous != null && previous.endTime == null &&
            snapshot.timestamp - previous.startTime < DrainThresholds.INCIDENT_COOLDOWN_MS
        ) {
            lastSleepIncident = previous.copy(
                peakCurrentMa = maxOf(peakMa, previous.peakCurrentMa),
                maxTemperatureCelsius = maxOf(maxTemp, previous.maxTemperatureCelsius),
            )
            return null
        }

        val critical = peakMa >= DrainThresholds.SLEEP_CRITICAL_MA ||
            maxTemp >= DrainThresholds.SLEEP_CRITICAL_TEMP_C

        val incident = Incident(
            startTime = window.first().timestamp,
            severity = if (critical) Severity.CRITICAL else Severity.MODERATE,
            peakCurrentMa = peakMa,
            maxTemperatureCelsius = maxTemp,
            diagnosis = "Rogue sleep drain (${peakMa} mA while screen off). " +
                "An app or wakelock is preventing deep sleep.",
            recommendedAction = "Open PowerWarden and force-stop the top consumer",
        )
        lastSleepIncident = incident
        return incident
    }

    // ── Screen ON: only unambiguous thermal runaway ───────────────────
    private fun evaluateActive(snapshot: Snapshot): Incident? {
        val thermal = (snapshot.tempC >= 42.0)
        if (snapshot.currentMa < DrainThresholds.ACTIVE_ANOMALY_MA || !thermal) return null

        val previous = lastActiveIncident
        if (previous != null && previous.endTime == null &&
            snapshot.timestamp - previous.startTime < DrainThresholds.INCIDENT_COOLDOWN_MS
        ) {
            lastActiveIncident = previous.copy(
                peakCurrentMa = maxOf(snapshot.currentMa, previous.peakCurrentMa),
                maxTemperatureCelsius = maxOf(snapshot.tempC, previous.maxTemperatureCelsius),
            )
            return null
        }

        val incident = Incident(
            startTime = snapshot.timestamp,
            severity = Severity.CRITICAL,
            peakCurrentMa = snapshot.currentMa,
            maxTemperatureCelsius = snapshot.tempC,
            culpritThread = "Thermal Runaway Loop",
            diagnosis = "Severe active discharge (${snapshot.currentMa} mA) with device " +
                "overheating (${"%.1f".format(snapshot.tempC)}°C).",
            recommendedAction = "Inspect heavy 3D/CPU tasks or reboot",
        )
        lastActiveIncident = incident
        return incident
    }

    /**
     * Closes any open incident whose condition has settled.
     *
     * @return the closed incident if one was just resolved, else null.
     */
    fun closeIfSettled(metrics: Map<String, Any>): Incident? {
        val currentMa = (metrics["currentMa"] as? Int) ?: 0
        val tempC = (metrics["temperatureCelsius"] as? Double) ?: 0.0
        val isScreenOn = (metrics["isScreenOn"] as? Boolean) ?: true
        val isCharging = (metrics["isCharging"] as? Boolean) ?: false
        val now = (metrics["timestamp"] as? Long) ?: System.currentTimeMillis()

        var closed: Incident? = null

        lastSleepIncident?.let { open ->
            if (open.endTime == null) {
                val settled = isCharging || isScreenOn ||
                    currentMa < DrainThresholds.SLEEP_ANOMALY_MA
                if (settled) {
                    val done = open.copy(endTime = now)
                    lastSleepIncident = done
                    closed = done
                }
            }
        }

        lastActiveIncident?.let { open ->
            if (open.endTime == null) {
                val settled = currentMa < DrainThresholds.ACTIVE_ANOMALY_MA || tempC < 42.0
                if (settled) {
                    val done = open.copy(endTime = now)
                    lastActiveIncident = done
                    closed = done
                }
            }
        }

        return closed
    }

    // ── Persistence ───────────────────────────────────────────────────
    fun persist(incident: Incident) {
        runCatching {
            val file = File(PowerWardenService.getDatabaseDir(context), "anomaly_incidents.jsonl")
            file.appendText(incident.toJson().toString() + "\n")
        }
    }

    /**
     * Rewrites the incident log so a closed record replaces its still-open
     * counterpart. JSONL has no in-place update, and incidents are few and small,
     * so a full rewrite is cheaper than any index.
     */
    fun persistClosure(closed: Incident) {
        runCatching {
            val file = File(PowerWardenService.getDatabaseDir(context), "anomaly_incidents.jsonl")
            if (!file.exists()) return@runCatching

            val out = StringBuilder()
            var replaced = false
            file.forEachLine { line ->
                if (line.isBlank()) return@forEachLine
                val parsed = runCatching { JSONObject(line) }.getOrNull()
                val isMatch = parsed != null &&
                    parsed.optLong("startTime", -1L) == closed.startTime &&
                    parsed.isNull("endTime") &&
                    !replaced
                if (isMatch) {
                    out.append(closed.toJson().toString()).append('\n')
                    replaced = true
                } else {
                    out.append(line).append('\n')
                }
            }
            if (!replaced) out.append(closed.toJson().toString()).append('\n')
            file.writeText(out.toString())
        }
    }

    // ── Alerting ──────────────────────────────────────────────────────
    /** Critical-only, at most one per 15 min and three per hour. */
    fun alertIfWarranted(incident: Incident) {
        if (incident.severity != Severity.CRITICAL) return

        val now = System.currentTimeMillis()
        while (recentAlerts.isNotEmpty() && now - recentAlerts.first() > 3_600_000L) {
            recentAlerts.removeFirst()
        }
        if (now - lastAlertAt < alertCooldownMs) return
        if (recentAlerts.size >= maxAlertsPerHour) return

        lastAlertAt = now
        recentAlerts.addLast(now)

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(manager)

        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = launch?.let {
            PendingIntent.getActivity(
                context,
                1006,
                it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        val body = incident.culpritPackage
            ?.takeIf { it.isNotBlank() }
            ?.let { "Rogue app: $it · Burning power in background." }
            ?: "${incident.peakCurrentMa} mA sustained draw with thermal elevation."

        val notification = NotificationCompat.Builder(context, ALERT_CHANNEL_ID)
            .setContentTitle("Critical Battery Drain (${incident.peakCurrentMa} mA)")
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_lock_idle_charging)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()

        runCatching { manager.notify(ALERT_NOTIFICATION_ID, notification) }
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (manager.getNotificationChannel(ALERT_CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                ALERT_CHANNEL_ID,
                "PowerWarden Alerts",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Alerts for sudden battery drain anomalies"
            },
        )
    }

    private companion object {
        const val ALERT_CHANNEL_ID = "power_warden_alerts"
        const val ALERT_NOTIFICATION_ID = 1001
    }
}
