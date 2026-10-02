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
        val portText = if (discoveredPort != null) "Detected Port: $discoveredPort" else "Searching for port via mDNS..."

        // RemoteInput for typing 6-digit code in notification
        val remoteInput = RemoteInput.Builder(KEY_PAIRING_CODE)
            .setLabel("Enter 6-digit pairing code")
            .build()

        val replyIntent = Intent(ACTION_CODE_SUBMITTED).apply {
            setPackage(context.packageName)
        }
        val replyPendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            replyIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_UPDATE_CURRENT
        )

        val replyAction = NotificationCompat.Action.Builder(
            android.R.drawable.ic_input_add,
            "Enter Code",
            replyPendingIntent
        )
            .addRemoteInput(remoteInput)
            .build()

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Pair Wireless Debugging")
            .setContentText(portText)
            .setStyle(NotificationCompat.BigTextStyle().bigText("Keep Developer Options open! Enter the 6-digit pairing code below without switching apps:\n$portText"))
            .setSmallIcon(android.R.drawable.ic_lock_idle_charging)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .addAction(replyAction)
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
                if (!code.isNullOrBlank()) {
                    onCodeReceivedListener?.invoke(code.trim())
                }
            }
        }
    }
}
