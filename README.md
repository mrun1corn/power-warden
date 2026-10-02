# Battery Watchdog 🔋🐕

> **Flutter + Native Android Sentinel for Silent Battery Drain & Runaway Process Detection**  
> Diagnoses hidden high-drain system anomalies without requiring Root or a PC.

---

## 🌟 The Problem
On modern Android devices, background processes or system services can enter infinite execution loops (e.g. `system_server`'s `CpuTracker`, misbehaving push workers, or stuck binder IPC calls). 

Because Android’s SELinux policy blocks unprivileged apps from inspecting `/proc/<pid>/` or querying process-level CPU tables, users experience rapid battery drain (10–25%/hr while idle), thermal buildup, and device throttling with **zero explanation in standard system battery settings**.

## 🎯 The Solution
**Battery Watchdog** uses a dual-tier approach:
1. **Tier 1 (Zero-ADB, Zero-Root):** Uses physical hardware feedback—instantaneous battery discharge current (`BATTERY_PROPERTY_CURRENT_NOW`), thermal status changes (`PowerManager.OnThermalStatusChangedListener`), and battery drain velocity during screen-off states—to detect that runaway drain is happening and alert the user immediately.
2. **Tier 2 (On-Device Shizuku / Wireless Debugging):** Leverages Android 11+ on-device Wireless Debugging (paired via Shizuku without a PC) to execute elevated diagnostics (`dumpsys batterystats`, `top`, `ps`) to pinpoint the **exact runaway process or thread**.

---

## 🏗️ Architecture Overview

```mermaid
graph TD
    subgraph Hardware & Android OS
        BATT[Battery Sensor: CURRENT_NOW]
        THERM[PowerManager: Thermal Status]
        SCRN[BroadcastReceiver: SCREEN_ON / SCREEN_OFF]
        SHIZ[Shizuku API: Wireless ADB]
    end

    subgraph Native Android [Kotlin Layer]
        FS[Watchdog Foreground Service] --> BATT
        FS --> THERM
        FS --> SCRN
        FS --> MC[MethodChannel / EventChannel]
        SHIZ --> FS
    end

    subgraph Flutter App [Dart Layer]
        MC --> Stream[Hardware Metric Stream]
        Stream --> AnomalyEngine[Anomaly Detection Engine]
        AnomalyEngine --> DB[(Local Drift/SQLite DB)]
        AnomalyEngine --> Notifs[Local Notifications]
        DB --> Dashboard[Flutter Analytics & Live Meter]
        ShizukuUI[Wireless Pair Assistant] --> SHIZ
    end
```

---

## 🚀 Key Features

* **Real-time Discharge Current Meter:** Direct read of instantaneous milliampere consumption ($mA$).
* **Screen-off Drain Sentinel:** Monitors battery drop rate specifically while the device is sleeping. If drain exceeds $500mA$ continuously or $>4\%/hr$ while the screen is off, a high-severity alert is dispatched.
* **Thermal Corroborator:** Correlates unexpected discharge spikes with thermal throttling states (`THERMAL_STATUS_MODERATE`, `SEVERE`) to filter out false positives.
* **Rootless Deep Inspection (Shizuku Integration):** Extracts thread-level CPU usage without a PC or root permissions.
* **Actionable Prescriptions:** Recommends specific remediation (e.g., system reboot for `system_server` loops, force-stopping rogue third-party background apps).
* **Negligible Overhead:** Background telemetry runs on configurable low-power intervals (1–2 minutes) using $<0.2\%$ battery per 24 hours.

---

## 📂 Documentation

* [Development & Implementation Plans](PLANS.md)
* [Technical Architecture Specification](ARCHITECTURE.md)

---

## 🛠️ Tech Stack

* **Frontend:** Flutter (Dart 3.x), Material 3, `fl_chart`
* **Native Android:** Kotlin, Android Foreground Service, BroadcastReceivers
* **Storage:** Drift (SQLite)
* **Privileged APIs:** Shizuku API (`dev.rikka.shizuku:api:13.1.5`)
* **Background Execution:** `flutter_foreground_task`
