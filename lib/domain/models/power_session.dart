class PowerSession {
  final String id;
  final String type; // 'charging' or 'discharging'
  final DateTime startTime;
  final DateTime endTime;
  final int startBatteryLevel;
  final int endBatteryLevel;
  final int totalMahDelta;
  final int peakMa;
  final double peakWatts;
  final double minTempCelsius;
  final double maxTempCelsius;
  final int screenOnSeconds;
  final int screenOffSeconds;
  final String topAppName;

  PowerSession({
    required this.id,
    required this.type,
    required this.startTime,
    required this.endTime,
    required this.startBatteryLevel,
    required this.endBatteryLevel,
    required this.totalMahDelta,
    required this.peakMa,
    required this.peakWatts,
    required this.minTempCelsius,
    required this.maxTempCelsius,
    this.screenOnSeconds = 0,
    this.screenOffSeconds = 0,
    this.topAppName = '',
  });

  bool get isCharging => type == 'charging';
  int get durationMinutes => endTime.difference(startTime).inMinutes;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'startBatteryLevel': startBatteryLevel,
      'endBatteryLevel': endBatteryLevel,
      'totalMahDelta': totalMahDelta,
      'peakMa': peakMa,
      'peakWatts': peakWatts,
      'minTempCelsius': minTempCelsius,
      'maxTempCelsius': maxTempCelsius,
      'screenOnSeconds': screenOnSeconds,
      'screenOffSeconds': screenOffSeconds,
      'topAppName': topAppName,
    };
  }

  factory PowerSession.fromMap(Map<String, dynamic> map) {
    return PowerSession(
      id: map['id'] as String,
      type: map['type'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['startTime'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(map['endTime'] as int),
      startBatteryLevel: map['startBatteryLevel'] as int,
      endBatteryLevel: map['endBatteryLevel'] as int,
      totalMahDelta: map['totalMahDelta'] as int,
      peakMa: map['peakMa'] as int,
      peakWatts: (map['peakWatts'] as num).toDouble(),
      minTempCelsius: (map['minTempCelsius'] as num).toDouble(),
      maxTempCelsius: (map['maxTempCelsius'] as num).toDouble(),
      screenOnSeconds: (map['screenOnSeconds'] as int?) ?? 0,
      screenOffSeconds: (map['screenOffSeconds'] as int?) ?? 0,
      topAppName: (map['topAppName'] as String?) ?? '',
    );
  }
}
