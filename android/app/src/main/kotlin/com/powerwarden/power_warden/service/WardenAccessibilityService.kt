package com.powerwarden.power_warden.service

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Native Accessibility Service that automatically performs the "Force Stop" sequence
 * on Android's native Settings App Info screen.
 *
 * Flow:
 * 1. App requests to stop a package.
 * 2. Service receives the target package name and opens system App Info settings.
 * 3. AccessibilityService inspects view nodes, clicks "Force Stop", confirms the dialog ("OK"),
 *    and presses BACK to return the user immediately to PowerWarden.
 *
 * This provides 100% rootless, zero-ADB automated force-stopping (identical to Greenify/SuperFreezZ).
 */
class WardenAccessibilityService : AccessibilityService() {

    companion object {
        var instance: WardenAccessibilityService? = null
            private set

        val isServiceRunning: Boolean
            get() = instance != null

        @Volatile
        private var targetPackageToStop: String? = null
        private val handler = Handler(Looper.getMainLooper())

        fun stopPackageAutomatically(packageName: String): Boolean {
            val service = instance ?: return false
            targetPackageToStop = packageName

            // Launch App Info settings screen
            val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = android.net.Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            service.startActivity(intent)
            return true
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (targetPackageToStop == null || event == null) return

        val rootNode = rootInActiveWindow ?: return

        // 1. Look for "Force stop" button on system App Info screen
        val forceStopNodes = rootNode.findAccessibilityNodeInfosByText("Force stop")
            .ifEmpty { rootNode.findAccessibilityNodeInfosByText("FORCE STOP") }

        for (node in forceStopNodes) {
            if (node.isClickable && node.isEnabled) {
                node.performAction(AccessibilityNodeInfo.ACTION_CLICK)

                // 2. Schedule confirmation click on popup dialog ("OK")
                handler.postDelayed({
                    confirmAndReturn()
                }, 180)
                return
            }
        }

        // Also check if dialog is already showing
        confirmAndReturn()
    }

    private fun confirmAndReturn() {
        val rootNode = rootInActiveWindow ?: return

        val okNodes = rootNode.findAccessibilityNodeInfosByText("OK")
            .ifEmpty { rootNode.findAccessibilityNodeInfosByText("Force stop") }

        for (node in okNodes) {
            if (node.isClickable && node.isEnabled) {
                node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                targetPackageToStop = null

                // 3. Immediately return back to PowerWarden
                handler.postDelayed({
                    performGlobalAction(GLOBAL_ACTION_BACK)
                }, 150)
                return
            }
        }
    }
}
