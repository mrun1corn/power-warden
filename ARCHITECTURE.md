# PowerWarden — Architecture & Technical Specification

## System Architecture

```
+---------------------------------------------------------------------------------+
|                                Flutter UI Layer                                 |
|  - Realtime Discharge Gauge & Thermal Stress Index                              |
|  - Historical Drain Timeline (fl_chart: current vs battery% vs screen-off)      |
|  - Anomaly Incident Feed & One-Tap Remediation (Kill/Restrict app)              |
|  - Wireless Debugging Assistant (Shizuku + Kadb on localhost)                   |
+----------------------------------------+----------------------------------------+
                                         | MethodChannel / EventChannel
+----------------------------------------v----------------------------------------+
|                          Native Android Layer (Kotlin)                          |
|                                                                                 |
|  +--------------------------------+       +----------------------------------+  |
|  | PowerWardenForegroundService   |       | ScreenStateReceiver              |  |
|  |  - FGS: specialUse (Android 14)|       |  - ACTION_SCREEN_ON              |  |
|  |  - Adaptive Low-CPU Ticker     |       |  - ACTION_SCREEN_OFF             |  |
|  +---------------+----------------+       +-----------------+----------------+  |
|                  |                                          |                   |
|  +---------------v------------------------------------------v----------------+  |
|  |                          Hardware Telemetry Probe                         |  |
|  |  - BatteryManager.BATTERY_PROPERTY_CURRENT_NOW (Auto scale & sign)        |  |
|  |  - PowerManager.OnThermalStatusChangedListener                            |  |
|  |  - BatteryManager.EXTRA_TEMPERATURE & Voltage                            |  |
|  |  - 3-point median filter to reject cellular bursts                        |  |
|  +-------------------------------+------------------------------------------+  |
|                                  |                                              |
|  +-------------------------------v------------------------------------------+  |
|  |             Elevated Diagnostics Engine (Triggered on Drain Spike)        |  |
|  |  - Shizuku Service Binder OR In-App Kadb (127.0.0.1 Wireless Debugging)  |  |
|  |  - Differential Snapshotting: top -b -n 1 (Snapshot A/B 5s delta)        |  |
|  |  - Wakelock Auditor: dumpsys batterystats --wake-locks                   |  |
|  |  - Active Mitigation: am force-stop / cmd appops set RUN_IN_BG ignore    |  |
|  +--------------------------------------------------------------------------+  |
+---------------------------------------------------------------------------------+
```

---

## Data Models

### 1. TelemetrySample
```dart
class TelemetrySample {
  final int id;
  final DateTime timestamp;
  final int batteryLevel;          // 0 - 100%
  final int currentMilliamps;       // Instantaneous discharge rate (positive = drain, negative = charge)
  final double temperatureCelsius;  // e.g. 38.5 C
  final int thermalStatus;          // PowerManager THERMAL_STATUS enum
  final bool isScreenOn;            // True if display was active
  final bool isCharging;            // True if plugged into AC/USB
  final int voltageMv;              // e.g. 4120 mV
}
```

### 2. AnomalyEvent
```dart
enum AnomalySeverity {
  mild,     // 300-500mA idle drain
  moderate, // 500-800mA idle drain
  critical  // >800mA idle drain + thermal elevation (stuck CPU core / wakelock)
}

class AnomalyEvent {
  final int id;
  final DateTime startTime;
  final DateTime? endTime;
  final AnomalySeverity severity;
  final int peakCurrentMa;
  final double maxTemperatureCelsius;
  final String? culpritPackage;     // e.g. "com.google.android.gms"
  final String? culpritThread;      // e.g. "CpuTracker" or "GcmService"
  final String diagnosis;           // Human-readable plain text explanation
  final String recommendedAction;   // e.g. "One-tap kill" or "Reboot recommended"
}
```

---

## Platform Channel Protocol

### MethodChannel: `com.powerwarden/telemetry`

| Method | Parameters | Returns | Description |
| :--- | :--- | :--- | :--- |
| `getInstantMetrics` | None | `Map<String, dynamic>` | Queries instantaneous calibrated current, temp, and charging status |
| `startWardenService` | `{ intervalMs: int }` | `bool` | Starts the background foreground service |
| `stopWardenService` | None | `bool` | Stops the foreground service |
| `getElevatedBackendStatus` | None | `Map<String, dynamic>` | Returns status for Shizuku (`hasShizuku`, `hasPermission`) and Kadb |
| `requestShizukuPermission` | None | `bool` | Requests user permission via Shizuku binder |
| `pairKadbLocal` | `{ port: int, code: String }` | `bool` | Pairs direct in-app Wireless Debugging on localhost |
| `runDeltaDiagnostics` | None | `Map<String, dynamic>` | Captures delta top + wakelock snapshot and returns culprits |
| `remediateApp` | `{ package: String, action: String }` | `bool` | Force-stops or restricts background execution via elevated ADB |

### EventChannel: `com.powerwarden/telemetry_stream`
Emits real-time hardware samples every tick:
```json
{
  "timestamp": 1727914800000,
  "level": 88,
  "currentMa": 740,
  "isDischarging": true,
  "temperatureCelsius": 39.0,
  "thermalStatus": 1,
  "isScreenOn": false,
  "voltageMv": 4120
}
```

---

## Power Budget Strategy

To ensure PowerWarden does not contribute to the drain it is monitoring:
1. **Adaptive Zero-Wake:** Back off completely during calm idle (15–60mA). Only tighten sampling when a drain or thermal threshold triggers.
2. **Zero Continuous Wakelocks:** Never hold `PARTIAL_WAKE_LOCK`. Let the Linux kernel deep sleep (`suspend`).
3. **Batch Persistence:** In-memory ring buffer flushed to SQLite in a single transaction once every 15 minutes.
4. **Execution Budget:** Hardware telemetry sample completes in $\le 10\text{ ms}$ of CPU time.
