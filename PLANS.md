# PowerWarden — MVP Engineering Roadmap & Execution Plan

> **Goal:** Ship a rock-solid, production-grade MVP that solves silent Android battery drain without root or a PC, maintaining $<0.3\%$ daily overhead, zero jank, and a refined Material 3 UI.

---

## 🎯 MVP Scope & Core Pillars

| Pillar | Target Specification |
| :--- | :--- |
| **Features** | Auto-calibrated live $mA$ current, screen-off drain sentinel, differential delta snapshotting ($top$ + wakelocks), one-tap Shizuku/ADB remediation, and translated diagnoses. |
| **Performance** | $<10\text{ms}$ CPU time per sample, zero continuous wakelocks (deep sleep preserved), 15-minute batched SQLite transactions, 60/120 FPS UI. |
| **Code Quality** | Clean layered architecture (Repository pattern), exhaustive unit tests for parsers/calibration, zero memory leaks, robust error handling across OEMs. |
| **UI / UX** | Material 3 Dark theme (OLED true black `#000000`), fluid animated gauges, clean `fl_chart` drain timeline, clear human-readable diagnoses instead of raw logs. |

---

## 🛠️ Detailed Phased Implementation

### Phase 1: Native Telemetry Core & OEM Normalization (Kotlin)
*Focus: Performance & Robustness*
- [ ] **1.1 Battery Probe (`BatteryProbe.kt`):**
  - Read `BATTERY_PROPERTY_CURRENT_NOW` with dynamic auto-scaling:
    - If $|raw| < 10,000$, treat as $mA$; if $|raw| \ge 10,000$, divide by $1,000$ to get $mA$.
  - Enforce sign standard: positive = discharge ($mA$), negative = charging ($mA$).
  - 3-point rolling median filter over 300ms to eliminate cellular transmission ping artifacts.
  - Read voltage ($mV$) and temperature ($^\circ C$) from sticky `ACTION_BATTERY_CHANGED`.
- [ ] **1.2 Thermal & Screen Observers (`ThermalObserver.kt`, `ScreenObserver.kt`):**
  - Register `PowerManager.OnThermalStatusChangedListener` (API 29+).
  - Register dynamic `BroadcastReceiver` for `ACTION_SCREEN_ON` and `ACTION_SCREEN_OFF`.
  - Track duration of screen-off sleep windows accurately across device Doze cycles.
- [ ] **1.3 Compliant Foreground Service (`PowerWardenService.kt`):**
  - Android 14/15 `specialUse` foreground service type with low-priority non-intrusive notification.
  - Adaptive Zero-Wake ticker:
    - Normal idle ($15\text{–}60mA$): Inexact 10-15 min wake intervals (let Linux kernel enter suspend).
    - Drain spike ($>350mA$ screen-off): Tighten to 30s diagnostics.
  - Guarantee sample execution completes within $\le 10\text{ ms}$ CPU wake budget.
- [ ] **1.4 Platform Channels (`TelemetryChannel.kt`):**
  - `MethodChannel` (`com.powerwarden/telemetry`) for on-demand metrics and service control.
  - `EventChannel` (`com.powerwarden/telemetry_stream`) for live HUD updates.

---

### Phase 2: Local Persistence & Anomaly Engine (Dart / Drift)
*Focus: Code Quality & Reliability*
- [ ] **2.1 Drift / SQLite Storage Engine:**
  - Define schema: `TelemetrySamplesTable` and `AnomalyIncidentsTable`.
  - In-memory ring buffer for 30 samples; flush to disk every 15 minutes to prevent flash I/O wakeups.
  - Automatic rolling retention cleanup: prune samples older than 48 hours.
- [ ] **2.2 Heuristic Anomaly Engine (`AnomalyEngine.dart`):**
  - Baseline profiling: Calculate moving average of idle screen-off consumption.
  - Detection triggers:
    - *Mild Anomaly:* Screen-off $>5$ min AND sustained $>400mA$ across 3 samples.
    - *Critical Anomaly:* Sustained $>750mA$ or $>4\%/hr$ drop with elevated thermals ($>38^\circ C$).
- [ ] **2.3 Local Notifications:**
  - Actionable system notifications alerting users of background drain with immediate "Inspect" action.

---

### Phase 3: Elevated Diagnostics & Differential Delta Engine
*Focus: Feature Intelligence (Smarter than Battery Guru)*
- [ ] **3.1 Elevated Backends (Shizuku + Kadb):**
  - Shizuku integration (`dev.rikka.shizuku:api:13.1.5`).
  - Native Kadb client integration (`com.flyfishxu:kadb:2.1.4`) for direct in-app Wireless Debugging on `localhost:5555`.
  - Unified executor interface (`PrivilegedExecutor`) abstracting Shizuku and Kadb.
- [ ] **3.2 Differential Delta Engine:**
  - Capture Snapshot A (`top -b -n 1 -m 10`, `dumpsys batterystats --wake-locks`).
  - Delay 5 seconds.
  - Capture Snapshot B.
  - Calculate delta ($\Delta$ CPU ticks per TID/PID and active wakelock holders) to isolate who is running *at that exact moment*.
- [ ] **3.3 Intelligent Translation & Remediation:**
  - Rulebook mapper:
    - `AudioMix` / Media wakelock held $\to$ "Media service stuck open in background".
    - `system_server / CpuTracker` $\to$ "System IPC contention loop (Reboot advised)".
    - Third-party app package $\to$ "Rogue background process".
  - One-tap remediation: `am force-stop <package>` or `cmd appops set <package> RUN_IN_BACKGROUND ignore`.

---

### Phase 4: Flutter UI / UX — Material 3 Minimalist Dashboard
*Focus: UI/UX & Polish*
- [ ] **4.1 Design System & Theme:**
  - Pure OLED Dark Theme (`#000000` background, high contrast dynamic accents, zero light bleed).
  - Consistent typography, subtle haptics on actions, and smooth micro-interactions.
- [ ] **4.2 Real-time Sentinel HUD:**
  - Live Discharge Current Dial: Color-coded arc gauge (green $<150mA$, amber $150\text{–}450mA$, red $>450mA$).
  - Metric Pills: Battery %, Temperature ($^\circ C$), Voltage ($mV$), Screen state, and Elevated Privileges badge (Shizuku/Kadb active).
- [ ] **4.3 Interactive Drain Timeline (`fl_chart`):**
  - Multi-series chart: Discharge current ($mA$) + Battery level (%) over time.
  - Shaded background vertical bands representing Screen-Off vs Screen-On windows.
  - Scrubbable tooltip detailing drain rate at any specific minute.
- [ ] **4.4 Anomaly Feed & Remediation Cards:**
  - Incident cards with severity badges, duration, peak $mA$, and translated root cause.
  - One-tap "Tame App" action button directly inside the card.
- [ ] **4.5 Pairing Assistant Modal:**
  - Guided step-by-step setup for Shizuku and direct Wireless Debugging (with port/pairing code inputs).

---

### Phase 5: Verification, Benchmarking & Packaging
*Focus: Performance Verification & Release*
- [ ] **5.1 CPU & Battery Overhead Benchmarking:**
  - Profile Native Service execution time with Android Studio Profiler (verify $<10ms$ CPU time per tick).
  - Verify total app 24-hour battery consumption is $<0.3\%$.
- [ ] **5.2 OEM Killer Defense Documentation & Settings:**
  - Whitelist prompt (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`).
  - Vendor autostart guide for Xiaomi (HyperOS), Samsung (OneUI), and OnePlus.
- [ ] **5.3 Automated CI/CD:**
  - GitHub Actions workflow for building debug and release APKs with automated linting and tests.
