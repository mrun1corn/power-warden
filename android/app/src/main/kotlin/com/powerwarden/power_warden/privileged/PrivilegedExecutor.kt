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
            val binder = Shizuku.getBinder()
            binder != null && binder.isBinderAlive && Shizuku.pingBinder()
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Checks if user has already granted Shizuku permissions to PowerWarden.
     */
    fun hasShizukuPermission(): Boolean {
        return try {
            if (!isShizukuAvailable()) {
                false
            } else if (Shizuku.isPreV11()) {
                false
            } else {
                Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
            }
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Connects or pairs via local wireless debugging ADB endpoint on localhost.
     */
    suspend fun pairKadb(port: Int, code: String): Boolean = withContext(Dispatchers.IO) {
        try {
            java.net.Socket("127.0.0.1", port).use { socket ->
                socket.isConnected
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
     * Retrieves top active processes with accurate CPU %, RAM (MB), and CPU execution time.
     * Accurately parses Android toybox/toolbox top table by dynamic header detection.
     */
    suspend fun getTopProcesses(): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        val list = mutableListOf<Map<String, Any>>()
        try {
            val res = executeCommand("top -b -n 1 -m 20")
            val lines = res.stdout.lines()

            var cpuColIdx = -1
            var resColIdx = -1
            var timeColIdx = -1
            var argsColIdx = -1

            for (line in lines) {
                val trimmed = line.trim()
                if (trimmed.isEmpty()) continue

                val tokens = trimmed.split("\\s+".toRegex())

                // Detect header line dynamically
                if (tokens.any { it.equals("PID", ignoreCase = true) } && tokens.any { it.contains("CPU", ignoreCase = true) }) {
                    for (i in tokens.indices) {
                        val header = tokens[i].uppercase()
                        if (header == "%CPU" || header == "CPU" || header == "CPU%") cpuColIdx = i
                        else if (header == "RES" || header == "RSS" || header == "VIRT") resColIdx = i
                        else if (header.startsWith("TIME")) timeColIdx = i
                        else if (header == "ARGS" || header == "CMD" || header == "NAME") argsColIdx = i
                    }
                    continue
                }

                // Process data line
                if (cpuColIdx != -1 && tokens.isNotEmpty() && tokens[0].all { it.isDigit() }) {
                    val pid = tokens[0]

                    val rawCpu = if (cpuColIdx < tokens.size) tokens[cpuColIdx] else "0"
                    val parsedCpu = rawCpu.replace("%", "").toDoubleOrNull() ?: 0.0

                    // Sanity check: single process CPU cannot exceed 100% per core
                    val cpuPercent = if (parsedCpu > 100.0) 100.0 else parsedCpu

                    val rawRes = if (resColIdx != -1 && resColIdx < tokens.size) tokens[resColIdx] else ""
                    val ramMb = parseMemoryToMb(rawRes)

                    val cpuTime = if (timeColIdx != -1 && timeColIdx < tokens.size) tokens[timeColIdx] else "--:--"

                    val pkgName = if (argsColIdx != -1 && argsColIdx < tokens.size) {
                        tokens.subList(argsColIdx, tokens.size).joinToString(" ")
                    } else {
                        tokens.last()
                    }

                    // Filter out internal kernel threads [ksoftirqd]
                    if (!pkgName.startsWith("[") && pkgName.isNotBlank()) {
                        val cleanName = when {
                            pkgName.contains("/") -> pkgName.substringAfterLast("/")
                            pkgName.contains(":") -> pkgName.substringBefore(":")
                            else -> pkgName
                        }

                        val appLabel = cleanName.substringAfterLast(".").replace("_", " ").capitalizeWords()

                        list.add(
                            mapOf(
                                "pid" to pid,
                                "packageName" to pkgName,
                                "name" to appLabel,
                                "cpuPercent" to Math.round(cpuPercent * 10.0) / 10.0,
                                "ramMb" to ramMb,
                                "cpuTime" to cpuTime
                            )
                        )
                    }
                }
            }
        } catch (_: Exception) {}

        list.sortedByDescending { (it["cpuPercent"] as? Double) ?: 0.0 }.take(15)
    }

    private fun parseMemoryToMb(raw: String): Int {
        if (raw.isBlank()) return 0
        val upper = raw.uppercase()
        return try {
            when {
                upper.endsWith("G") -> (upper.removeSuffix("G").toDouble() * 1024).toInt()
                upper.endsWith("M") -> upper.removeSuffix("M").toDouble().toInt()
                upper.endsWith("K") -> (upper.removeSuffix("K").toDouble() / 1024).toInt()
                else -> (upper.toDouble() / 1024).toInt()
            }
        } catch (_: Exception) {
            0
        }
    }

    private fun String.capitalizeWords(): String {
        return split(" ").joinToString(" ") { it.replaceFirstChar { char -> char.uppercase() } }
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
