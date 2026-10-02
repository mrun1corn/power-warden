# Battery Watchdog — Implementation & Development Plans

## Overview
This document outlines the phased roadmap for building **Battery Watchdog** from initial native hardware probing to full Flutter dashboard visualization and Shizuku integration.

---

## Phase 1: Native Android Hardware Telemetry Bridge (Kotlin)
- [ ] **1.1 Battery Hardware Interface:**
  - Implement `BatteryManager.BATTERY_PROPERTY_CURRENT_NOW` sampling (reading instantaneous $\mu A$).
  - Convert negative microamperes into positive discharge current ($mA$) and charging currents.
  - Implement fallback handling for OEMs returning microamperes inverted or in milliamperes.
  - Read battery temperature via `Intent.ACTION_BATTERY_CHANGED`.
- [ ] **1.2 Thermal & Throttling Observers:**
  - Register `PowerManager.OnThermalStatusChangedListener` (Android 10+ / API 29).
  - Map `THERMAL_STATUS_NONE` through `THERMAL_STATUS_CRITICAL` to standardized severity levels.
- [ ] **1.3 Screen State Ingestion:**
  - Register dynamic `BroadcastReceiver` for `Intent.ACTION_SCREEN_ON` and `Intent.ACTION_SCREEN_OFF`.
  - Maintain a state machine tracking exact duration of screen-off sleep windows.
- [ ] **1.4 Low-Overhead Native Foreground Service:**
  - Implement an Android foreground service with a low-priority notification channel.
  - Set up an alarm/timer ticker to sample metrics every 60–120 seconds while the screen is off.
  - Ensure sample execution completes within $<15ms$ to prevent CPU wakeup penalty.

---

## Phase 2: Anomaly Detection Engine (Dart / Kotlin)
- [ ] **2.1 Baseline Profiling:**
  - Measure normal device idle current consumption ($50\text{–}120mA$ on standard Android flagships with radios active).
  - Identify ambient background baseline per device.
- [ ] **2.2 Screen-Off Drain Detector:**
  - If `screen_state == OFF` and `current_ma > 500mA` for $\ge 3$ consecutive sampling intervals:
    - Escalate to `WARNING_RUNAWAY_DRAIN`.
  - If sustained for $>10$ minutes with elevated thermal status:
    - Escalate to `CRITICAL_RUNAWAY_DRAIN`.
- [ ] **2.3 Contention Benchmark Heuristic:**
  - Run a lightweight, deterministic math loop (e.g. 100,000 iterations of SHA-256) on an isolated background isolate.
  - If execution takes $>4\times$ the baseline duration during screen-off, trigger CPU starvation alert.
- [ ] **2.4 Notification Dispatcher:**
  - Issue actionable local notifications (e.g., *"High background drain detected (740mA). A background thread is consuming a full CPU core. Tap to inspect or reboot."*).

---

## Phase 3: Shizuku / Local ADB Integration (Rootless Deep Inspection)
- [ ] **3.1 Shizuku SDK Binding:**
  - Integrate `dev.rikka.shizuku:api:13.1.5` and `dev.rikka.shizuku:provider:13.1.5`.
  - Implement permission request flow and check if Shizuku service is running.
- [ ] **3.2 Elevated Shell Executor:**
  - Execute rootless shell commands via `Shizuku.newProcess`:
    - `dumpsys batterystats --charged`
    - `top -b -n 1 -s 9`
    - `cat /proc/stat`
- [ ] **3.3 Diagnostics Parser:**
  - Parse `top` thread outputs to isolate specific thread names (`CpuTracker`, `system_server`, etc.).
  - Match PID/TID to package name using `pm list packages -U`.
  - Provide direct culprit naming in the anomaly report.

---

## Phase 4: Flutter User Interface & Analytics
- [ ] **4.1 Architecture & State Management:**
  - Set up Flutter project structure with `flutter_bloc` or `riverpod`.
  - Set up `Drift` / `SQLite` database to persist historical battery samples and drain events.
- [ ] **4.2 Real-time Dashboard:**
  - Live discharge current dial / gauge ($mA$).
  - Temperature meter and thermal throttle badge.
  - Screen state indicator.
- [ ] **4.3 Historical Drain Charts:**
  - Time-series chart (`fl_chart`) plotting:
    - Battery percentage (blue line)
    - Instantaneous discharge current (red line)
    - Screen on/off intervals (shaded background bands)
- [ ] **4.4 Anomaly History & Incident Log:**
  - List of detected anomaly events with timestamps, peak discharge rate, and duration.
  - Culprit details (if Shizuku enabled) or symptom diagnosis (if pure tier-1).

---

## Phase 5: Power Budget, Hardening & Release
- [ ] **5.1 Dogfooding & Power Budget:**
  - Verify that the app's own 24-hour battery consumption is below $0.5\%$.
  - Optimize database write batching (write samples in memory, flush to disk every 15 minutes).
- [ ] **5.2 OEM Compatibility:**
  - Guide users on disabling aggressive OEM battery optimizers (MIUI/HyperOS, Samsung OneUI, OxygenOS) that kill foreground services.
- [ ] **5.3 Release Preparation:**
  - Android 14 and Android 15 compatibility validation (`FOREGROUND_SERVICE_SPECIAL_USE` permission declarations).
  - Open-source release and GitHub Actions CI.
