package com.powerwarden.power_warden

import android.content.Intent
import android.os.Build
import androidx.annotation.NonNull
import com.powerwarden.power_warden.privileged.PrivilegedExecutor
import com.powerwarden.power_warden.service.PowerWardenService
import com.powerwarden.power_warden.telemetry.BatteryProbe
import com.powerwarden.power_warden.telemetry.ScreenObserver
import com.powerwarden.power_warden.telemetry.ThermalObserver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.powerwarden/telemetry"
    private val EVENT_CHANNEL = "com.powerwarden/telemetry_stream"

    private lateinit var batteryProbe: BatteryProbe
    private lateinit var thermalObserver: ThermalObserver
    private lateinit var screenObserver: ScreenObserver
    private lateinit var privilegedExecutor: PrivilegedExecutor
    private lateinit var mdnsDiscovery: com.powerwarden.power_warden.privileged.AdbMdnsDiscovery
    private lateinit var pairingNotificationHelper: com.powerwarden.power_warden.service.PairingNotificationHelper

    private val activityScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        batteryProbe = BatteryProbe(this)
        thermalObserver = ThermalObserver(this) {}
        screenObserver = ScreenObserver(this) { _, _ -> }
        privilegedExecutor = PrivilegedExecutor(this)
        mdnsDiscovery = com.powerwarden.power_warden.privileged.AdbMdnsDiscovery(this)
        pairingNotificationHelper = com.powerwarden.power_warden.service.PairingNotificationHelper(this)

        mdnsDiscovery.onPairingPortDiscovered = { port ->
            // Always post pairing notification when an active pairing service is broadcasting on the network
            pairingNotificationHelper.showPairingNotification(port)
        }

        // Auto-start discovery and attempt auto-reconnect on launch
        mdnsDiscovery.startDiscovery()
        activityScope.launch {
            privilegedExecutor.autoReconnect()
        }

        com.powerwarden.power_warden.service.PairingNotificationHelper.onCodeReceivedListener = { code ->
            val pairingPort = mdnsDiscovery.discoveredPairingPort
            val connectPort = mdnsDiscovery.discoveredConnectPort
            if (pairingPort != null) {
                activityScope.launch {
                    val ok = privilegedExecutor.pairKadb(pairingPort, code, connectPort)
                    if (ok) {
                        pairingNotificationHelper.dismiss()
                    }
                }
            }
        }

        mdnsDiscovery.onConnectPortDiscovered = { port ->
            activityScope.launch {
                privilegedExecutor.connectKadb(port)
            }
        }

        thermalObserver.start()
        screenObserver.start()

        // Ensure notification permission on Android 13+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 2001)
            }
        }

        // Hook background service listener into EventSink
        PowerWardenService.listener = { sample ->
            activityScope.launch {
                eventSink?.success(sample)
            }
        }

        // MethodChannel handler
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstantMetrics" -> {
                    val snap = batteryProbe.readInstantaneousSample()
                    val map = mapOf(
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
                    result.success(map)
                }
                "startWardenService" -> {
                    val intent = Intent(this, PowerWardenService::class.java).apply {
                        action = PowerWardenService.ACTION_START
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopWardenService" -> {
                    val intent = Intent(this, PowerWardenService::class.java).apply {
                        action = PowerWardenService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                "openWirelessDebuggingSettings" -> {
                    mdnsDiscovery.startDiscovery()
                    pairingNotificationHelper.showPairingNotification(mdnsDiscovery.discoveredPairingPort)

                    val intents = listOf(
                        // Intent 1: Direct Wireless Debugging Sub-Fragment (Android 11+)
                        Intent("android.settings.WIRELESS_DEBUGGING_SETTINGS"),
                        // Intent 2: Standard Developer Settings with deep fragment target
                        Intent(android.provider.Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS).apply {
                            putExtra(":settings:show_fragment", "com.android.settings.development.WirelessDebuggingFragment")
                        },
                        // Intent 3: General Developer Settings fallback
                        Intent(android.provider.Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS),
                        // Intent 4: Global Settings fallback
                        Intent(android.provider.Settings.ACTION_SETTINGS)
                    )

                    var opened = false
                    for (intent in intents) {
                        try {
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            opened = true
                            break
                        } catch (_: Exception) {}
                    }
                    result.success(opened)
                }
                "startMdnsDiscovery" -> {
                    mdnsDiscovery.startDiscovery()
                    pairingNotificationHelper.showPairingNotification(mdnsDiscovery.discoveredPairingPort)
                    result.success(true)
                }
                "stopMdnsDiscovery" -> {
                    mdnsDiscovery.stopDiscovery()
                    pairingNotificationHelper.dismiss()
                    result.success(true)
                }
                "getDiscoveredPort" -> {
                    result.success(mdnsDiscovery.discoveredPairingPort ?: 0)
                }
                "getElevatedBackendStatus" -> {
                    val hasShizuku = privilegedExecutor.isShizukuAvailable()
                    val hasPerm = privilegedExecutor.hasShizukuPermission()
                    val hasKadb = privilegedExecutor.hasKadbConnected()
                    val hasPermAdb = privilegedExecutor.hasPermanentAdbPermissions()
                    val statusMap = mapOf(
                        "hasShizuku" to hasShizuku,
                        "hasShizukuPermission" to hasPerm,
                        "hasPermission" to hasPerm,
                        "hasKadb" to hasKadb,
                        "hasPermanentAdb" to hasPermAdb,
                        "hasAnyElevatedAccess" to (hasPerm || hasKadb || hasPermAdb)
                    )
                    result.success(statusMap)
                }
                "requestShizukuPermission" -> {
                    if (privilegedExecutor.isShizukuAvailable()) {
                        try {
                            rikka.shizuku.Shizuku.requestPermission(1001)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "pairKadbLocal" -> {
                    val port = call.argument<Int>("port") ?: 5555
                    val code = call.argument<String>("code") ?: ""
                    val connectPort = mdnsDiscovery.discoveredConnectPort
                    activityScope.launch {
                        val ok = privilegedExecutor.pairKadb(port, code, connectPort)
                        result.success(ok)
                    }
                }
                "connectKadbLocal" -> {
                    val port = call.argument<Int>("port") ?: (mdnsDiscovery.discoveredConnectPort ?: 5555)
                    activityScope.launch {
                        val ok = privilegedExecutor.connectKadb(port)
                        result.success(ok)
                    }
                }
                "getRunningProcesses" -> {
                    activityScope.launch {
                        val procs = privilegedExecutor.getTopProcesses()
                        result.success(procs)
                    }
                }
                "getHistoricalAppUsage" -> {
                    val days = call.argument<Int>("days") ?: 1
                    activityScope.launch {
                        val history = privilegedExecutor.getHistoricalAppUsage(days)
                        result.success(history)
                    }
                }
                "runDeltaDiagnostics" -> {
                    activityScope.launch {
                        val diag = privilegedExecutor.runDifferentialDiagnostics()
                        result.success(diag)
                    }
                }
                "remediateApp" -> {
                    val pkg = call.argument<String>("package") ?: ""
                    val act = call.argument<String>("action") ?: "force_stop"
                    activityScope.launch {
                        val success = privilegedExecutor.remediateApp(pkg, act)
                        result.success(success)
                    }
                }
                "openAccessibilitySettings" -> {
                    try {
                        val intent = android.content.Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "isAccessibilityServiceActive" -> {
                    result.success(com.powerwarden.power_warden.service.WardenAccessibilityService.isServiceRunning)
                }
                "getSharedPrefBool" -> {
                    val key = call.argument<String>("key") ?: ""
                    val defaultVal = call.argument<Boolean>("default") ?: false
                    val prefs = getSharedPreferences("power_warden_ui", android.content.Context.MODE_PRIVATE)
                    result.success(prefs.getBoolean(key, defaultVal))
                }
                "setSharedPrefBool" -> {
                    val key = call.argument<String>("key") ?: ""
                    val value = call.argument<Boolean>("value") ?: false
                    getSharedPreferences("power_warden_ui", android.content.Context.MODE_PRIVATE)
                        .edit()
                        .putBoolean(key, value)
                        .apply()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // EventChannel handler
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    override fun onDestroy() {
        thermalObserver.stop()
        screenObserver.stop()
        activityScope.cancel()
        super.onDestroy()
    }
}
