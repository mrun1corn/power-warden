package com.powerwarden.power_warden.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Posts an ongoing notification with a Direct Reply RemoteInput field.
 * Allows users to enter the 6-digit Wireless Debugging code directly from their status bar
 * or lock screen without leaving the Developer Options Wireless Debugging screen!
 */
class PairingNotificationHelper(private val context: Context) {

    companion object {
        const val CHANNEL_ID = "power_warden_pairing"
        const val NOTIFICATION_ID = 9001
        const val ACTION_CODE_SUBMITTED = "com.powerwarden.action.PAIRING_CODE_SUBMITTED"
        const val KEY_PAIRING_CODE = "key_pairing_code"

        var onCodeReceivedListener: ((String) -> Unit)? = null
    }

    private val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    init {
        createChannel()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Wireless Debugging Helper",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Enter pairing code directly from the notification"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    fun showPairingNotification(discoveredPort: Int?) {
        if (discoveredPort != null && discoveredPort > 0) {
            context.getSharedPreferences("power_warden_adb", Context.MODE_PRIVATE)
                .edit()
                .putInt("last_pairing_port", discoveredPort)
                .apply()
        }

        val portText = if (discoveredPort != null) "Detected Port: $discoveredPort" else "Searching for port via mDNS..."

        val openSettingsIntent = Intent("android.settings.WIRELESS_DEBUGGING_SETTINGS").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val openSettingsPending = PendingIntent.getActivity(
            context,
            1003,
            openSettingsIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        // Compact RemoteInput label so input text is never pushed off-screen
        val remoteInput = RemoteInput.Builder(KEY_PAIRING_CODE)
            .setLabel("6-digit code")
            .build()

        val replyIntent = Intent(context, CodeReceiver::class.java).apply {
            action = ACTION_CODE_SUBMITTED
            setPackage(context.packageName)
            if (discoveredPort != null && discoveredPort > 0) {
                putExtra("discovered_pairing_port", discoveredPort)
            }
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val replyPendingIntent = PendingIntent.getBroadcast(
            context,
            1002,
            replyIntent,
            flags
        )

        val replyAction = NotificationCompat.Action.Builder(
            android.R.drawable.ic_input_add,
            "Enter Code",
            replyPendingIntent
        )
            .addRemoteInput(remoteInput)
            .build()

        val portShort = if (discoveredPort != null) "Port: $discoveredPort" else "Waiting for port..."

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Wireless ADB Pairing Helper")
            .setContentText("$portShort · Tap 'Enter Code' below")
            .setSmallIcon(android.R.drawable.ic_lock_idle_charging)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .addAction(replyAction)
            .addAction(android.R.drawable.ic_menu_preferences, "Settings", openSettingsPending)
            .build()

        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    fun dismiss() {
        notificationManager.cancel(NOTIFICATION_ID)
    }

    class CodeReceiver : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            if (intent?.action == ACTION_CODE_SUBMITTED) {
                val remoteInput = RemoteInput.getResultsFromIntent(intent)
                val code = remoteInput?.getCharSequence(KEY_PAIRING_CODE)?.toString()
                if (!code.isNullOrBlank() && ctx != null) {
                    val cleanCode = code.trim()
                    val port = intent.getIntExtra("discovered_pairing_port", -1)

                    // Execute pairing even if MainActivity was paused by Developer Options
                    val pendingResult = goAsync()
                    kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
                        try {
                            val executor = com.powerwarden.power_warden.privileged.PrivilegedExecutor(ctx.applicationContext)
                            val finalPort = if (port > 0) port else {
                                ctx.getSharedPreferences("power_warden_adb", Context.MODE_PRIVATE)
                                    .getInt("last_pairing_port", -1)
                            }

                            if (finalPort > 0) {
                                executor.pairKadb(finalPort, cleanCode)
                                val notifMgr = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                                notifMgr?.cancel(NOTIFICATION_ID)
                            }
                        } finally {
                            pendingResult.finish()
                        }
                    }
                    onCodeReceivedListener?.invoke(cleanCode)
                }
            }
        }
    }
}
