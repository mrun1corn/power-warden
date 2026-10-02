# Battery Watchdog — Architecture & Technical Specification

## System Architecture

```
+-------------------------------------------------------------+
|                        Flutter UI Layer                      |
|  - Realtime Discharge Gauge                                 |
|  - Historical Drain Timeline (fl_chart)                     |
|  - Anomaly Incident Log & Remediation Actions                |
+------------------------------+------------------------------+
                               | MethodChannel / EventChannel
+------------------------------v------------------------------+
|                   Native Android Layer (Kotlin)             |
|                                                             |
|  +------------------------+   +---------------------------+  |
|  | WatchdogForegroundSvc  |   | ScreenStateReceiver       |  |
|  |  - Periodic Ticker     |   |  - ACTION_SCREEN_ON       |  |
|  |  - Low CPU Wakeup      |   |  - ACTION_SCREEN_OFF      |  |
|  +-----------+------------+   +-------------+-------------+  |
|              |                              |                |
|  +-----------v------------------------------v-------------+  |
|  |                 Telemetry Collector                    |  |
|  |  - BatteryManager.BATTERY_PROPERTY_CURRENT_NOW         |  |
|  |  - PowerManager.OnThermalStatusChangedListener         |  |
|  |  - BatteryManager.EXTRA_TEMPERATURE                   |  |
|  +---------------------------+----------------------------+  |
|                              |                               |
|  +---------------------------v----------------------------+  |
|  |              Elevated Shizuku Diagnostics              |  |
|  |  - Shizuku.newProcess ("top -b -n 1")                  |  |
|  |  - Thread Parser (Resolves PID/TID to package)         |  |
|  +--------------------------------------------------------+  |
+-------------------------------------------------------------+
```

---

## Data Models

### 1. TelemetrySample
```dart
class TelemetrySample {
  final int id;
  final DateTime timestamp;
  final int batteryLevel;         // 0 - 100%
  final int currentMilliamps;      // Instantaneous discharge rate (positive = drain, negative = charge)
  final double temperatureCelsius; // e.g. 38.5 C
  final int thermalStatus;         // PowerManager THERMAL_STATUS enum
  final bool isScreenOn;           // True if display was active
  final bool isCharging;           // True if plugged into AC/USB
}
```

### 2. AnomalyEvent
```dart
enum AnomalySeverity {
  mild,     // e.g. 300-500mA idle drain
  moderate, // 500-800mA idle drain
  critical  // >800mA idle drain + thermal elevation (stuck CPU core)
}

class AnomalyEvent {
  final int id;
  final DateTime startTime;
  final DateTime? endTime;
  final AnomalySeverity severity;
  final int peakCurrentMa;
  final double maxTemperatureCelsius;
  final String? culpritProcess;    // Populated if Shizuku is active (e.g. "system_server / CpuTracker")
  final String recommendedAction; // e.g. "Reboot recommended"
}
```

---

## Platform Channel Protocol

### MethodChannel: `com.example.battery_watchdog/telemetry`

| Method | Parameters | Returns | Description |
| :--- | :--- | :--- | :--- |
| `getInstantMetrics` | None | `Map<String, dynamic>` | Queries instantaneous current, temp, and charging status |
| `startWatchdogService` | `{ intervalMs: int }` | `bool` | Starts the background foreground service |
| `stopWatchdogService` | None | `bool` | Stops the foreground service |
| `isShizukuAvailable` | None | `bool` | Checks if Shizuku is installed and running |
| `requestShizukuPermission` | None | `bool` | Requests user permission via Shizuku binder |
| `runDeepDiagnostics` | None | `Map<String, dynamic>` | Executes elevated thread inspection via Shizuku |

### EventChannel: `com.example.battery_watchdog/telemetry_stream`
Emits real-time hardware samples every tick:
```json
{
  "timestamp": 1727914800000,
  "level": 88,
  "currentMa": 740,
  "isDischarging": true,
  "temperatureCelsius": 39.0,
  "thermalStatus": 1,
  "isScreenOn": false
}
```

---

## Power Budget Strategy

To ensure Battery Watchdog does not contribute to the drain it is monitoring:
1. **Zero Wakelocks:** Never acquire a continuous `PARTIAL_WAKE_LOCK`. Rely strictly on `AlarmManager` or `WorkManager` with inexact alarms.
2. **Batch Persistence:** Store telemetry in an in-memory ring buffer (up to 30 samples). Flush to SQLite in a single transaction once every 15 minutes.
3. **Execution Budget:** Telemetry read must complete within $\le 10\text{ ms}$ of CPU time per sample.
