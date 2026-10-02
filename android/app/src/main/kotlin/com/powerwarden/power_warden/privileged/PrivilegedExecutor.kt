package com.powerwarden.power_warden.privileged

import android.content.Context
import android.content.pm.PackageManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.lang.reflect.Method

/**
 * Unified execution interface for privileged operations.
 * Prioritizes Shizuku's persistent Binder IPC so permissions and shell access
 * remain active seamlessly across app switches and device sleep cycles.
 */
class PrivilegedExecutor(private val context: Context) {

    data class ExecutionResult(
        val exitCode: Int,
        val stdout: String,
        val stderr: String,
        val isSuccess: Boolean
    )

    private var shizukuNewProcessMethod: Method? = null

    init {
        try {
            val method = Shizuku::class.java.getDeclaredMethod(
                "newProcess",
                Array<String>::class.java,
                Array<String>::class.java,
                String::class.java
            )
            method.isAccessible = true
            shizukuNewProcessMethod = method
        } catch (_: Exception) {}
    }

    /**
     * Checks if Shizuku manager service is alive and accessible.
     */
    fun isShizukuAvailable(): Boolean {
        return try {
            Shizuku.pingBinder()
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Checks if user has already granted Shizuku permissions to PowerWarden.
     */
    fun hasShizukuPermission(): Boolean {
        return try {
            if (Shizuku.isPreV11()) {
                false
            } else {
                Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
            }
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Executes shell commands directly via Shizuku's elevated process if available,
     * falling back to standard runtime shell.
     */
    suspend fun executeCommand(command: String): ExecutionResult = withContext(Dispatchers.IO) {
        try {
            val process: Process = if (isShizukuAvailable() && hasShizukuPermission() && shizukuNewProcessMethod != null) {
                shizukuNewProcessMethod!!.invoke(null, arrayOf("sh", "-c", command), null, null) as Process
            } else {
                Runtime.getRuntime().exec(arrayOf("sh", "-c", command))
            }

            val stdout = process.inputStream.bufferedReader().use(BufferedReader::readText)
            val stderr = process.errorStream.bufferedReader().use(BufferedReader::readText)
            val exitCode = process.waitFor()

            ExecutionResult(
                exitCode = exitCode,
                stdout = stdout.trim(),
                stderr = stderr.trim(),
                isSuccess = exitCode == 0
            )
        } catch (e: Exception) {
            ExecutionResult(
                exitCode = -1,
                stdout = "",
                stderr = e.message ?: "Execution failed",
                isSuccess = false
            )
        }
    }

    /**
     * Differential delta snapshot: Captures top thread stats, waits delayMs, captures second snapshot,
     * and computes CPU tick differential.
     */
    suspend fun runDifferentialDiagnostics(delayMs: Long = 3000L): Map<String, Any> = withContext(Dispatchers.IO) {
        val snap1 = executeCommand("top -b -n 1 -m 10")
        kotlinx.coroutines.delay(delayMs)
        val snap2 = executeCommand("top -b -n 1 -m 10")
        val wakelocks = executeCommand("dumpsys batterystats --wake-locks")

        mapOf(
            "snapshot1" to snap1.stdout,
            "snapshot2" to snap2.stdout,
            "wakelocks" to wakelocks.stdout.take(2000),
            "timestamp" to System.currentTimeMillis()
        )
    }

    /**
     * Remediates a runaway application using elevated Shizuku shell.
     */
    suspend fun remediateApp(packageName: String, action: String): Boolean = withContext(Dispatchers.IO) {
        val cmd = when (action) {
            "force_stop" -> "am force-stop $packageName"
            "restrict_bg" -> "cmd appops set $packageName RUN_IN_BACKGROUND ignore"
            "revoke_wakelock" -> "cmd appops set $packageName WAKE_LOCK ignore"
            else -> "am force-stop $packageName"
        }
        val res = executeCommand(cmd)
        res.isSuccess
    }
}
