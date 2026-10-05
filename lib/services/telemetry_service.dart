import 'dart:async';
import 'package:flutter/services.dart';
import '../domain/models/telemetry_sample.dart';

/// Service managing communication across native MethodChannel and EventChannel.
class TelemetryService {
  static const MethodChannel _methodChannel = MethodChannel('com.powerwarden/telemetry');
  static const EventChannel _eventChannel = EventChannel('com.powerwarden/telemetry_stream');

  Stream<TelemetrySample>? _sampleStream;

  /// Fetches an instantaneous calibrated sample on-demand.
  Future<TelemetrySample> getInstantMetrics() async {
    try {
      final res = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('getInstantMetrics');
      if (res != null) {
        return TelemetrySample.fromMap(Map<String, dynamic>.from(res));
      }
    } catch (e) {
      // Fallback
    }
    return TelemetrySample(
      timestamp: DateTime.now(),
      batteryLevel: 50,
      currentMilliamps: 120,
      temperatureCelsius: 32.0,
      thermalStatus: 0,
      isScreenOn: true,
      isCharging: false,
      voltageMv: 4000,
    );
  }

  /// Starts the native Android Foreground Service.
  Future<bool> startForegroundService() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('startWardenService');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Stops the native Android Foreground Service.
  Future<bool> stopForegroundService() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('stopWardenService');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks elevated backend status (Shizuku, Kadb).
  Future<Map<String, bool>> getElevatedStatus() async {
    try {
      final res = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('getElevatedBackendStatus');
      if (res != null) {
        return {
          'hasShizuku': (res['hasShizuku'] as bool?) ?? false,
          'hasShizukuPermission': (res['hasShizukuPermission'] as bool?) ?? false,
          'hasPermission': (res['hasPermission'] as bool?) ?? false,
          'hasKadb': (res['hasKadb'] as bool?) ?? false,
          'hasPermanentAdb': (res['hasPermanentAdb'] as bool?) ?? false,
          'hasAnyElevatedAccess': (res['hasAnyElevatedAccess'] as bool?) ?? false,
        };
      }
    } catch (_) {}
    return {
      'hasShizuku': false,
      'hasShizukuPermission': false,
      'hasPermission': false,
      'hasKadb': false,
      'hasPermanentAdb': false,
      'hasAnyElevatedAccess': false,
    };
  }

  Future<bool> openWirelessDebuggingSettings() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('openWirelessDebuggingSettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestShizukuPermission() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('requestShizukuPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startMdnsDiscovery() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('startMdnsDiscovery');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopMdnsDiscovery() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('stopMdnsDiscovery');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<int> getDiscoveredPort() async {
    try {
      final res = await _methodChannel.invokeMethod<int>('getDiscoveredPort');
      return res ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getRunningProcesses() async {
    try {
      final res = await _methodChannel.invokeListMethod<dynamic>('getRunningProcesses');
      if (res != null) {
        return res.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Retrieves subsystem power consumption (CPU, Wakelock, Wi-Fi) directly from `dumpsys batterystats`.
  Future<Map<String, Map<String, double>>> getEstimatedAppPowerStats() async {
    try {
      final res = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('getEstimatedAppPowerStats');
      if (res != null) {
        final converted = <String, Map<String, double>>{};
        res.forEach((key, value) {
          if (value is Map) {
            converted[key.toString()] = Map<String, double>.from(
              value.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
            );
          }
        });
        return converted;
      }
    } catch (_) {}
    return {};
  }

  Future<bool> pairKadb(int port, String code) async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('pairKadbLocal', {
        'port': port,
        'code': code,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> connectKadb(int port) async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('connectKadbLocal', {
        'port': port,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Runs differential diagnostics via elevated engine.
  Future<Map<String, dynamic>> runDeltaDiagnostics() async {
    try {
      final res = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('runDeltaDiagnostics');
      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    return {};
  }

  /// Retrieves aggregated historical app energy and time usage.
  Future<List<Map<String, dynamic>>> getHistoricalAppUsage({int days = 1}) async {
    try {
      final res = await _methodChannel.invokeListMethod<dynamic>('getHistoricalAppUsage', {'days': days});
      if (res != null) {
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Requests exemption from Android & OEM battery optimizations (HyperOS/MIUI/Samsung).
  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if PowerWarden is exempt from battery saver / sleeping restrictions.
  Future<bool> isBatteryOptimizationIgnored() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('isBatteryOptimizationIgnored');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Remediates a rogue application via elevated ADB.
  Future<bool> remediateApp(String packageName, {String action = 'force_stop'}) async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('remediateApp', {
        'package': packageName,
        'action': action,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Manually attempts Kadb connect on a port
  Future<bool> connectKadbLocal(int port) async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('connectKadbLocal', {'port': port});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android Accessibility Settings.
  Future<bool> openAccessibilitySettings() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('openAccessibilitySettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if Warden Accessibility Service is running.
  Future<bool> isAccessibilityServiceActive() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('isAccessibilityServiceActive');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Reads a boolean from native SharedPreferences.
  Future<bool> getPrefBool(String key, {bool defaultValue = false}) async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('getSharedPrefBool', {
        'key': key,
        'default': defaultValue,
      });
      return res ?? defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  /// Writes a boolean to native SharedPreferences.
  Future<bool> setPrefBool(String key, bool value) async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('setSharedPrefBool', {
        'key': key,
        'value': value,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Subscribes to live stream of hardware telemetry samples.
  Stream<TelemetrySample> get telemetryStream {
    _sampleStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => TelemetrySample.fromMap(Map<String, dynamic>.from(event as Map)));
    return _sampleStream!;
  }
}
