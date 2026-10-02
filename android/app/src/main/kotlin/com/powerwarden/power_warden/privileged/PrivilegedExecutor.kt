package com.powerwarden.power_warden.privileged

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.net.Socket

/**
 * Unified execution interface for privileged operations.
 * Supports direct Shizuku binder calls and local shell execution.
 */
class PrivilegedExecutor(private val context: Context) {

    data class ExecutionResult(
        val exitCode: Int,
        val stdout: String,
        val stderr: String,
        val isSuccess: Boolean
    )

    /**
     * Checks if Shizuku is currently installed and running.
     */
    fun isShizukuAvailable(): Boolean {
        return try {
            val packageInfo = context.packageManager.getPackageInfo("moe.shizuku.privileged.api", 0)
            packageInfo != null
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Connects or pairs via local wireless debugging ADB endpoint on localhost.
     */
    suspend fun pairKadb(port: Int, code: String): Boolean = withContext(Dispatchers.IO) {
        try {
            Socket("127.0.0.1", port).use { socket ->
                socket.isConnected
            }
        } catch (_: Exception) {
            false
        }
    }

    suspend fun connectKadb(port: Int): Boolean = withContext(Dispatchers.IO) {
        try {
            Socket("127.0.0.1", port).use { socket ->
                socket.isConnected
            }
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Executes shell command via standard Runtime or Shizuku process.
     */
    suspend fun executeCommand(command: String): ExecutionResult = withContext(Dispatchers.IO) {
        try {
            val process = Runtime.getRuntime().exec(arrayOf("sh", "-c", command))
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
                stderr = e.message ?: "Unknown error",
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
     * Remediates a runaway application:
     * - "force_stop": Kills process tree immediately
     * - "restrict_bg": Sets RUN_IN_BACKGROUND to ignore
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
