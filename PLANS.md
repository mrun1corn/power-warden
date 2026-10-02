# PowerWarden — Implementation & Development Plans

## Overview
This document outlines the phased roadmap for building **PowerWarden** from native hardware telemetry probing to differential delta diagnostic profiling, Shizuku & Kadb integration, and a reactive Flutter dashboard.

---

## Phase 1: Native Android Hardware Telemetry Bridge (Kotlin)
- [ ] **1.1 Battery Hardware Interface (`BatteryProbe.kt`):**
  - Sample `BatteryManager.BATTERY_PROPERTY_CURRENT_NOW` with dynamic $\mu A$ vs $mA$ scaling.
  - Implement sign normalization: positive discharge current ($mA$), negative charging current ($mA$).
  - 3-point rolling median filter to suppress cellular/modem bursts.
  - Read battery temperature and voltage via `Intent.ACTION_BATTERY_CHANGED`.
- [ ] **1.2 Thermal & Throttling Observers (`ThermalObserver.kt`):**
  - Register `PowerManager.OnThermalStatusChangedListener` (Android 10+ / API 29).
  - Map `THERMAL_STATUS_NONE` through `THERMAL_STATUS_CRITICAL` to standardized severity levels.
- [ ] **1.3 Screen State Ingestion (`ScreenStateReceiver.kt`):**
  - Register dynamic `BroadcastReceiver` for `Intent.ACTION_SCREEN_ON` and `Intent.ACTION_SCREEN_OFF`.
  - Maintain a state machine tracking exact duration of screen-off sleep windows.
- [ ] **1.4 Foreground Service (`PowerWardenService.kt`):**
  - Implement an Android foreground service with `specialUse` type (Android 14/15 compliant).
  - Adaptive Zero-Wake ticker: relax during nominal idle (15–60mA), tighten during drain spikes.
  - Ensure sample execution completes within $<10ms$ CPU time.
  - Expose `MethodChannel` (`com.powerwarden/telemetry`) and `EventChannel` (`com.powerwarden/telemetry_stream`).

---

## Phase 2: Anomaly Engine & Incident Profiler (Dart / Kotlin)
- [ ] **2.1 Baseline Profiling:**
  - Auto-learn device idle baseline current consumption ($50\text{–}120mA$ on standard Android flagships).
- [ ] **2.2 Screen-Off Drain Detector:**
  - If `screen_state == OFF` and `current_ma > 450mA` across 3 consecutive cycles:
    - Escalate to `WARNING_RUNAWAY_DRAIN`.
  - If sustained for $>10$ minutes with elevated thermal status ($>38^\circ\text{C}$):
    - Escalate to `CRITICAL_RUNAWAY_DRAIN`.
- [ ] **2.3 Differential Snapshotting Engine:**
  - On anomaly trigger: Capture Snapshot A (`top`, `dumpsys batterystats --wake-locks`), wait 5 seconds, capture Snapshot B, diff active threads and unreleased wakelocks.
- [ ] **2.4 Notification Dispatcher:**
  - Dispatch actionable local notifications with culprit package/thread and direct one-tap fix buttons.

---

## Phase 3: Rootless Elevated Diagnostics (Shizuku + Kadb)
- [ ] **3.1 Shizuku Integration:**
  - Integrate `dev.rikka.shizuku:api:13.1.5` and `dev.rikka.shizuku:provider:13.1.5`.
  - Check binder availability, handle one-time permission request, execute privileged commands.
- [ ] **3.2 In-App Kadb (Direct Wireless ADB Client):**
  - Integrate `com.flyfishxu:kadb:2.1.4`.
  - In-app pairing flow for Android 11+ Wireless Debugging over loopback (`127.0.0.1`).
  - Auto-reconnect via mDNS port discovery.
- [ ] **3.3 Privileged Remediator:**
  - One-tap "Tame App": Execute `am force-stop <package>` or `cmd appops set <package> RUN_IN_BACKGROUND ignore`.
  - Identify system loops vs third-party apps to recommend reboots vs app kills.

---

## Phase 4: Flutter User Interface & Analytics
- [ ] **4.1 Architecture & Persistence:**
  - Scaffold Flutter project structure (Material 3).
  - Set up `Drift` / `SQLite` database to persist historical battery samples and drain events with a 48h rolling prune.
- [ ] **4.2 Real-time Dashboard:**
  - Live discharge current gauge / dial ($mA$).
  - Temperature meter, voltage readout, and thermal throttle badge.
  - Elevated status badge (Shizuku / Kadb active).
- [ ] **4.3 Historical Drain Charts:**
  - Time-series chart (`fl_chart`) plotting:
    - Battery percentage (blue line)
    - Instantaneous discharge current (red line)
    - Screen on/off intervals (shaded background bands)
- [ ] **4.4 Anomaly Feed & Incident Log:**
  - List of detected anomaly incidents with timestamps, peak discharge rate, duration, and culprit thread.
  - Action button to kill or restrict culprit directly from UI.

---

## Phase 5: Power Budget, Hardening & Release
- [ ] **5.1 Power Budget Verification:**
  - Verify app's own 24-hour battery consumption is below $<0.3\%$.
  - Batch database writes in-memory, flushing every 15 minutes.
- [ ] **5.2 OEM Killer Defense:**
  - Add whitelist guide for MIUI/HyperOS, Samsung OneUI, ColorOS.
  - Shortcut to `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
- [ ] **5.3 Release Preparation:**
  - Configure GitHub Actions CI workflow to build release APKs and run unit tests.
