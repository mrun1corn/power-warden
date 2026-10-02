class TelemetrySample {
  final int? id;
  final DateTime timestamp;
  final int batteryLevel; // 0 - 100%
  final int currentMilliamps; // Discharge rate (positive = drain, negative = charge)
  final double temperatureCelsius; // e.g. 38.5 C
  final int thermalStatus; // PowerManager THERMAL_STATUS enum (0-6)
  final bool isScreenOn; // True if display was active
  final bool isCharging; // True if plugged into AC/USB
  final int voltageMv; // e.g. 4120 mV

  const TelemetrySample({
    this.id,
    required this.timestamp,
    required this.batteryLevel,
    required this.currentMilliamps,
    required this.temperatureCelsius,
    required this.thermalStatus,
    required this.isScreenOn,
    required this.isCharging,
    required this.voltageMv,
  });

  TelemetrySample copyWith({
    int? id,
    DateTime? timestamp,
    int? batteryLevel,
    int? currentMilliamps,
    double? temperatureCelsius,
    int? thermalStatus,
    bool? isScreenOn,
    bool? isCharging,
    int? voltageMv,
  }) {
    return TelemetrySample(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      currentMilliamps: currentMilliamps ?? this.currentMilliamps,
      temperatureCelsius: temperatureCelsius ?? this.temperatureCelsius,
      thermalStatus: thermalStatus ?? this.thermalStatus,
      isScreenOn: isScreenOn ?? this.isScreenOn,
      isCharging: isCharging ?? this.isCharging,
      voltageMv: voltageMv ?? this.voltageMv,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'batteryLevel': batteryLevel,
      'currentMilliamps': currentMilliamps,
      'temperatureCelsius': temperatureCelsius,
      'thermalStatus': thermalStatus,
      'isScreenOn': isScreenOn,
      'isCharging': isCharging,
      'voltageMv': voltageMv,
    };
  }

  factory TelemetrySample.fromMap(Map<String, dynamic> map) {
    // Handle both naming styles (e.g. from event channel: level, currentMa, etc.)
    final rawTimestamp = map['timestamp'];
    final DateTime parsedTimestamp;
    if (rawTimestamp is int) {
      parsedTimestamp = DateTime.fromMillisecondsSinceEpoch(rawTimestamp);
    } else if (rawTimestamp is String) {
      parsedTimestamp = DateTime.tryParse(rawTimestamp) ?? DateTime.now();
    } else {
      parsedTimestamp = DateTime.now();
    }

    final batteryLevel = (map['batteryLevel'] ?? map['level'] ?? 0) as int;
    final current = (map['currentMilliamps'] ?? map['currentMa'] ?? 0) as int;
    final temp = ((map['temperatureCelsius'] ?? map['temperature'] ?? 0.0) as num).toDouble();
    final thermal = (map['thermalStatus'] ?? 0) as int;
    final screenOn = (map['isScreenOn'] ?? false) as bool;
    final charging = (map['isCharging'] ?? !(map['isDischarging'] ?? true)) as bool;
    final voltage = (map['voltageMv'] ?? map['voltage'] ?? 0) as int;

    return TelemetrySample(
      id: map['id'] as int?,
      timestamp: parsedTimestamp,
      batteryLevel: batteryLevel,
      currentMilliamps: current,
      temperatureCelsius: temp,
      thermalStatus: thermal,
      isScreenOn: screenOn,
      isCharging: charging,
      voltageMv: voltage,
    );
  }
}
