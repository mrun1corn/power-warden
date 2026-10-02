# PowerWarden — Comprehensive Engineering Plan & Specification

> **Mission:** Build a high-precision, low-overhead Android battery sentinel and runaway process killer without root or a PC.
> **Targets:** $<0.3\%$ daily battery consumption, zero continuous wakelocks, $\le 10\text{ ms}$ CPU wake budget per poll, 60/120 FPS UI, and clear human diagnoses.

---

## 🏛️ System Architecture & Phase Interlock

```
+---------------------------------------------------------------------------------------------------+
|                                      PHASE 4: FLUTTER UI / UX                                     |
|  - Material 3 OLED Dark Engine (#000000)      - Animated Instantaneous Current Gauge (CustomPainter)|
|  - Multi-Axis Drain Timeline (fl_chart)       - Incident Action Cards with 1-Tap Mitigation       |
|  - Wireless Debugging Setup Modal (Kadb/Shizuku)                                                  |
+-------------------------------------------------+-------------------------------------------------+
                                                  | MethodChannel & EventChannel
+-------------------------------------------------v-------------------------------------------------+
|                                 PHASE 2: DART / DRIFT DATA & ANOMALY                              |
|  - Drift SQLite Engine (48h rolling retention)   - In-Memory Ring Buffer (15-min flush batching)   |
|  - EWMA Idle Baseline Estimator                  - Screen-Off Velocity & Thermal Anomaly Evaluator|
|  - System Notification Dispatcher with Deep-Link Payloads                                         |
+-------------------------------------------------+-------------------------------------------------+
                                                  | Diagnostic Requests & IPC Triggers
+-------------------------------------------------v-------------------------------------------------+
|                     PHASE 3: ELEVATED ROOTLESS DIAGNOSTICS & DELTA ENGINE                         |
|  - Unified PrivilegedExecutor Interface                                                           |
|    ├── Provider A: Shizuku Binder API (dev.rikka.shizuku:api:13.1.5)                              |
|    └── Provider B: On-Device Kadb Client (com.flyfishxu:kadb:2.1.4 over localhost:5555)           |
|  - Differential Delta Profiler (Snapshot A -> 5s delay -> Snapshot B -> Delta diff)               |
|  - Parser Matrix: `top -H` threads, `dumpsys batterystats --wake-locks`, `pm list packages -U`   |
|  - Automated Translation Rulebook (Maps IPC/Audio/Wakelock signatures to plain English)           |
|  - Active Mitigation: `am force-stop`, `cmd appops set RUN_IN_BACKGROUND ignore`                   |
+-------------------------------------------------+-------------------------------------------------+
                                                  | Low-Level Hardware Samples
+-------------------------------------------------v-------------------------------------------------+
|                        PHASE 1: NATIVE KOTLIN TELEMETRY CORE & OEM CALIBRATION                    |
|  - BatteryProbe: BATTERY_PROPERTY_CURRENT_NOW with auto-scaling (uA vs mA) & sign inversion fix   |
|  - 3-Point Rolling Median Filter (removes 300ms cellular burst artifacts)                         |
|  - ThermalObserver: PowerManager.OnThermalStatusChangedListener (API 29+)                         |
|  - ScreenObserver: BroadcastReceiver tracking exact screen-off sleep epochs                       |
|  - PowerWardenService: Android 14/15 `specialUse` FGS with Adaptive Zero-Wake ticker              |
+---------------------------------------------------------------------------------------------------+
```

---

## 📋 Comprehensive Phase Specifications

### 🔬 Phase 1: Native Telemetry Core & OEM Normalization (Kotlin)
**Core Objectives:** Accurate hardware readings, zero sleep disruptions, and strict $\le 10\text{ ms}$ CPU wake budget.

#### 1.1 Hardware Battery Probing (`BatteryProbe.kt`)
* **Scale Normalization:**
  * Raw property: `BatteryManager.BATTERY_PROPERTY_CURRENT_NOW`.
  * Threshold logic:
    $$\text{Scale Factor} = \begin{cases} 1.0 & \text{if } |I_{\text{raw}}| < 10{,}000 \text{ (Device reports } mA) \\ 0.001 & \text{if } |I_{\text{raw}}| \ge 10{,}000 \text{ (Device reports } \mu A) \end{cases}$$
* **Sign Polarity Correction:**
  * Some OEM kernels (e.g., Xiaomi MIUI/HyperOS builds) invert discharge/charge signs.
  * Query `BatteryManager.EXTRA_STATUS` from `registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))`.
  * Standardize:
    * Discharging: $I > 0\text{ mA}$ (positive represents system drain).
    * Charging: $I < 0\text{ mA}$ (negative represents incoming energy).
* **3-Point Median Noise Filter:**
  * Cellular modems and Wi-Fi radios produce transient power spikes lasting 50–200ms.
  * Probe takes 3 samples spaced 100ms apart:
    $$I_{\text{clean}} = \text{median}(I_1, I_2, I_3)$$
  * Returns filtered current, temperature ($0.1^\circ\text{C}$ precision), voltage ($mV$), and battery capacity ($0\text{–}100\%$).

#### 1.2 Thermal & Screen Observers (`ThermalObserver.kt`, `ScreenObserver.kt`)
* **Thermal Observer:**
  * Registers `PowerManager.OnThermalStatusChangedListener` (API 29+).
  * Maps Android thermal status:
    * `0: NONE`, `1: LIGHT`, `2: MODERATE`, `3: SEVERE`, `4: CRITICAL`, `5: EMERGENCY`, `6: SHUTDOWN`.
* **Screen State Observer:**
  * Listens dynamically for `Intent.ACTION_SCREEN_ON` and `Intent.ACTION_SCREEN_OFF`.
  * Maintains monotonic timestamp (`SystemClock.elapsedRealtime()`) tracking exact sleep window duration.

#### 1.3 Compliant Foreground Service (`PowerWardenService.kt`)
* **Android 14/15 Compliance:**
  * Declares `android:foregroundServiceType="specialUse"`.
  * Manifest property: `android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE` = `"Silent battery drain monitoring and hardware telemetry"`.
  * Silent, low-importance notification (`IMPORTANCE_MIN`) with `FOREGROUND_SERVICE_IMMEDIATE`.
* **Adaptive Zero-Wake Ticker:**
  * **Calm Idle ($15\text{–}60\text{ mA}$):** Polling interval backs off to inexact 10–15 minutes via `AlarmManager.setAndAllowWhileIdle()`. Device remains in Linux kernel `suspend` (Deep Sleep).
  * **Active Drain Spike ($>350\text{ mA}$ while screen-off):** Dynamically escalates to a 30-second diagnostics cycle.
  * **Hard Constraint:** Sample cycle execution must finish in $\le 10\text{ ms}$ CPU time.

#### 1.4 Native Platform Channels (`TelemetryBridge.kt`)
* `MethodChannel` (`com.powerwarden/telemetry`):
  * `getInstantMetrics()` $\to$ `{ currentMa, tempC, voltageMv, level, isCharging, thermalStatus, isScreenOn }`
  * `startService(intervalMs)`, `stopService()`
* `EventChannel` (`com.powerwarden/telemetry_stream`):
  * Streams real-time samples at 1Hz when the app UI is open and foregrounded.

---

### 💾 Phase 2: Local Persistence & Anomaly Engine (Dart / Drift)
**Core Objectives:** Zero flash I/O wakes, rolling data pruning, and reliable detection of silent drain anomalies.

#### 2.1 Drift Storage Architecture (`database.dart`)
* **Schema Design:**
  * `TelemetrySamples`: `id` (int PK auto), `timestamp` (DateTime, indexed), `currentMa` (int), `batteryLevel` (int), `temperature` (double), `voltageMv` (int), `thermalStatus` (int), `isScreenOn` (bool, indexed).
  * `AnomalyIncidents`: `id` (int PK auto), `startTime` (DateTime), `endTime` (DateTime nullable), `severity` (enum: mild, moderate, critical), `peakCurrentMa` (int), `maxTemp` (double), `culpritPackage` (text nullable), `culpritThread` (text nullable), `diagnosis` (text), `isRemediated` (bool).
* **In-Memory Ring Buffer & Flush Policy:**
  * Holds up to 30 samples in a Dart in-memory buffer.
  * Flushes to SQLite in a single transaction every 15 minutes or immediately upon Anomaly Incident detection.
* **Rolling Pruning Worker:**
  * Daily background maintenance runs: `DELETE FROM telemetry_samples WHERE timestamp < NOW() - INTERVAL 48 HOURS`.

#### 2.2 Anomaly Detection Heuristics (`anomaly_engine.dart`)
* **Baseline Profiling:**
  * Computes Exponentially Weighted Moving Average (EWMA) of idle current:
    $$\text{Baseline}_{t} = \alpha \cdot I_{\text{sample}} + (1 - \alpha) \cdot \text{Baseline}_{t-1} \quad (\alpha = 0.05)$$
* **Trigger Conditions:**
  * **Mild Anomaly:** Screen off $\ge 5\text{ min}$ AND current $> 400\text{ mA}$ for 3 consecutive readings.
  * **Moderate Anomaly:** Screen off $\ge 5\text{ min}$ AND current $> 600\text{ mA}$ OR drain rate $> 3\%/\text{hr}$.
  * **Critical Anomaly:** Current $> 800\text{ mA}$ with `thermalStatus >= MODERATE` ($>38^\circ\text{C}$) OR drain rate $> 5\%/\text{hr}$ (indicates stuck CPU spinloop).
* **Trigger Action:** Instantly fires Phase 3 Elevated Diagnostics if Shizuku or Kadb is connected.

#### 2.3 Local Notifications (`notification_service.dart`)
* Actionable system notification:
  * Title: *"⚡ High Idle Drain Detected: 680mA"*
  * Body: *"Screen is off but a process is consuming excessive power. Tap to inspect."*
  * Direct action buttons: `[ Inspect Now ]` / `[ Dismiss ]`.

---

### ⚡ Phase 3: Elevated Rootless Diagnostics & Delta Engine (Shizuku + Kadb)
**Core Objectives:** Attributing drain to exact threads *in the moment* (rather than cumulative averages) and providing rootless remediation.

#### 3.1 Dual Elevated Backends (`PrivilegedExecutor`)
* **Interface Contract:**
  ```kotlin
  interface PrivilegedExecutor {
      fun isAvailable(): Boolean
      fun hasPermission(): Boolean
      suspend fun execute(command: String): ShellResult
  }
  ```
* **Backend A — Shizuku (`ShizukuExecutor.kt`):**
  * Hooks `Shizuku.addRequestPermissionResultListener` and `Shizuku.newProcess()`.
  * Persistent one-time authorization per installation.
* **Backend B — In-App Kadb (`KadbExecutor.kt`):**
  * Integrates `com.flyfishxu:kadb:2.1.4`.
  * Connects over loopback `127.0.0.1:5555` via Android 11+ Wireless Debugging.
  * Automatically resolves dynamic ports via mDNS (`KadbMdnsAndroid`).

#### 3.2 Differential Delta Engine (`DeltaProfiler.kt`)
* **The Problem:** Cumulative dumpsys or `top` stats show who used CPU over the last 12 hours, hiding a spike that started 2 minutes ago.
* **The Solution (Differential Snapshotting):**
  1. **Snapshot 1 ($T_0$):** Run `top -b -n 1 -H -m 15` (thread-level CPU ticks) + `dumpsys batterystats --wake-locks`.
  2. **Pause Window:** Sleep 5.0 seconds.
  3. **Snapshot 2 ($T_0 + 5s$):** Run identical commands.
  4. **Delta Calculation:**
     $$\Delta\text{CPU Ticks} = \text{Ticks}_2(TID) - \text{Ticks}_1(TID)$$
     $$\Delta\text{Wakelock Time} = \text{HeldTime}_2(UID) - \text{HeldTime}_1(UID)$$
  5. **Resolution:** Map UID to package name using `pm list packages --uid <UID>`.

#### 3.3 Rulebook Translation & Diagnosis
* Technical signature parser matches patterns to human-understandable diagnoses:
  * `AudioMix` wakelock held continuously while screen off $\to$ **"Audio hardware lock not released by media player"**.
  * `system_server` with thread `CpuTracker` or `Binder:*` spinning $\to$ **"Android IPC contention loop (Reboot recommended)"**.
  * `com.google.android.gms` with `*job*` or `GcmService` spinning $\to$ **"Google Play Services sync retry loop due to poor network"**.
  * User-installed third-party app with high $\Delta\text{CPU}$ $\to$ **"Rogue background process: <App Name>"**.

#### 3.4 Rootless Remediation (`AppRemediator.kt`)
* One-tap actions executed via elevated ADB shell:
  * Force Stop: `am force-stop <package>`
  * Restrict Background: `cmd appops set <package> RUN_IN_BACKGROUND ignore`
  * Revoke WakeLock Privilege: `cmd appops set <package> WAKE_LOCK ignore`

---

### 🎨 Phase 4: Flutter UI / UX — Material 3 Minimalist Dashboard
**Core Objectives:** Fluid 60/120 FPS animations, true OLED dark theme, and intuitive actionable metrics.

#### 4.1 Design System & OLED Theming
* **Color Palette:**
  * Background: `#000000` (True OLED pitch black — saves display battery).
  * Surface / Cards: `#121212` with subtle `#222222` borders.
  * Status Emerald (Normal $<150\text{ mA}$): `#00E676`
  * Status Amber (Warning $150\text{–}450\text{ mA}$): `#FFB300`
  * Status Crimson (Critical $>450\text{ mA}$): `#FF1744`
  * Accent Cyan (Charging): `#00E5FF`

#### 4.2 Real-Time Sentinel HUD
* **Instantaneous Discharge Dial (`CurrentGauge.dart`):**
  * CustomPainter 240-degree sweep arc gauge.
  * Shows live $mA$ with spring-physics needle animation (`flutter_animate`).
  * Center readout: Large typography showing current value + polarity indicator (`DRAINING` / `CHARGING`).
* **Metric Chips:**
  * Battery % (with estimated time remaining).
  * Temperature (color-coded badge: Normal $<36^\circ\text{C}$, Warm $36\text{–}40^\circ\text{C}$, Hot $>40^\circ\text{C}$).
  * Voltage ($mV$).
  * Elevated Backend Status (Pill button showing `Shizuku: Active`, `Wireless ADB: Active`, or `Setup Needed`).

#### 4.3 Multi-Axis Drain Timeline (`DrainTimelineChart.dart`)
* Built with `fl_chart`:
  * Left Axis: Instantaneous Current ($mA$, red/green gradient line).
  * Right Axis: Battery Level ($0\text{–}100\%$, smooth cyan line).
  * Background Bands: Shaded semi-transparent vertical grey blocks for `Screen-Off` intervals.
  * Scrubbing Tooltip: Long-press or drag scrub cursor to view exact timestamp, $mA$, temperature, and screen state at that minute.

#### 4.4 Anomaly Feed & Incident Cards (`AnomalyCard.dart`)
* Incident cards displaying:
  * Severity badge (`MILD`, `MODERATE`, `CRITICAL`).
  * Time detected and total duration.
  * Peak drain rate ($mA$) and temperature reached.
  * Plain English diagnosis.
  * Culprit breakdown (Package name, thread name, % delta CPU).
  * Direct action buttons: `[ Tame App ]` (runs `am force-stop`) or `[ Restrict Background ]`.

#### 4.5 Pairing Assistant Modal (`WirelessPairingSheet.dart`)
* Bottom sheet assistant with two tabs:
  * **Tab 1: Shizuku:** Detects Shizuku installation, displays status, and provides one-tap "Request Permission" button.
  * **Tab 2: Direct Wireless ADB (Kadb):** Guided instructions with input fields for Port and 6-digit Pairing Code to connect on `localhost` without third-party apps.

---

### 🛡️ Phase 5: Verification, Benchmarking & Packaging
**Core Objectives:** Enforce battery budgets, prevent OEM process kills, and automate delivery.

#### 5.1 Overhead & Battery Profiling
* **CPU Execution Verification:**
  * Profile `PowerWardenService` sampling routine via Android Studio CPU Profiler.
  * Assert execution time $\le 10\text{ ms}$ per sample.
* **Overhead Validation:**
  * Run 24-hour test with screen off.
  * Verify PowerWarden's own contribution via `dumpsys batterystats` is $<0.3\%$ total battery drain.

#### 5.2 OEM Killer Defense
* **Battery Optimization Exemption:**
  * Check `PowerManager.isIgnoringBatteryOptimizations()`.
  * Trigger `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` dialog.
* **Vendor Autostart Guides:**
  * Built-in OEM detection (Xiaomi MIUI/HyperOS, Samsung OneUI, OnePlus/Oppo ColorOS).
  * Direct deep-link intents to system autostart manager pages.

#### 5.3 Automated CI/CD (GitHub Actions)
* `.github/workflows/build.yml`:
  * Runs `flutter analyze` and `flutter test`.
  * Runs Kotlin unit tests (`./gradlew test`).
  * Builds unsigned release APKs and universal APK artifacts.
