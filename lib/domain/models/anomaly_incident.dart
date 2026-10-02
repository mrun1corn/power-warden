enum AnomalySeverity {
  mild,
  moderate,
  critical,
}

class AnomalyIncident {
  final int? id;
  final DateTime startTime;
  final DateTime? endTime;
  final AnomalySeverity severity;
  final int peakCurrentMa;
  final double maxTemperatureCelsius;
  final String? culpritPackage;
  final String? culpritThread;
  final String diagnosis;
  final bool isRemediated;
  final String? recommendedAction;

  const AnomalyIncident({
    this.id,
    required this.startTime,
    this.endTime,
    required this.severity,
    required this.peakCurrentMa,
    required this.maxTemperatureCelsius,
    this.culpritPackage,
    this.culpritThread,
    required this.diagnosis,
    this.isRemediated = false,
    this.recommendedAction,
  });

  AnomalyIncident copyWith({
    int? id,
    DateTime? startTime,
    DateTime? endTime,
    AnomalySeverity? severity,
    int? peakCurrentMa,
    double? maxTemperatureCelsius,
    String? culpritPackage,
    String? culpritThread,
    String? diagnosis,
    bool? isRemediated,
    String? recommendedAction,
  }) {
    return AnomalyIncident(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      severity: severity ?? this.severity,
      peakCurrentMa: peakCurrentMa ?? this.peakCurrentMa,
      maxTemperatureCelsius:
          maxTemperatureCelsius ?? this.maxTemperatureCelsius,
      culpritPackage: culpritPackage ?? this.culpritPackage,
      culpritThread: culpritThread ?? this.culpritThread,
      diagnosis: diagnosis ?? this.diagnosis,
      isRemediated: isRemediated ?? this.isRemediated,
      recommendedAction: recommendedAction ?? this.recommendedAction,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime?.millisecondsSinceEpoch,
      'severity': severity.name,
      'peakCurrentMa': peakCurrentMa,
      'maxTemperatureCelsius': maxTemperatureCelsius,
      'culpritPackage': culpritPackage,
      'culpritThread': culpritThread,
      'diagnosis': diagnosis,
      'isRemediated': isRemediated,
      'recommendedAction': recommendedAction,
    };
  }

  factory AnomalyIncident.fromMap(Map<String, dynamic> map) {
    return AnomalyIncident(
      id: map['id'] as int?,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['startTime'] as int),
      endTime: map['endTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['endTime'] as int)
          : null,
      severity: AnomalySeverity.values.byName(map['severity'] as String),
      peakCurrentMa: map['peakCurrentMa'] as int,
      maxTemperatureCelsius: (map['maxTemperatureCelsius'] as num).toDouble(),
      culpritPackage: map['culpritPackage'] as String?,
      culpritThread: map['culpritThread'] as String?,
      diagnosis: map['diagnosis'] as String,
      isRemediated: (map['isRemediated'] as bool?) ?? false,
      recommendedAction: map['recommendedAction'] as String?,
    );
  }
}
