import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/anomaly_incident.dart';
import '../../domain/models/telemetry_sample.dart';

/// Lightweight, zero-code-gen Local Persistence Engine.
/// Stores telemetry samples and anomaly incidents with in-memory ring-buffer batching (every 15 min),
/// preventing continuous flash I/O wakes and pruning records older than 48 hours.
class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  File? _telemetryFile;
  File? _anomaliesFile;

  final List<TelemetrySample> _memoryBuffer = [];
  Timer? _flushTimer;
  Timer? _pruneTimer;

  static const int maxBufferSize = 30;
  static const Duration flushInterval = Duration(minutes: 15);
  static const Duration retentionPeriod = Duration(hours: 48);

  Future<void> initialize() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbDir = Directory(p.join(docsDir.path, 'power_warden_data'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    _telemetryFile = File(p.join(dbDir.path, 'telemetry_samples.jsonl'));
    _anomaliesFile = File(p.join(dbDir.path, 'anomaly_incidents.jsonl'));

    startPeriodicTasks();
  }

  void startPeriodicTasks() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(flushInterval, (_) => flushBuffer());

    _pruneTimer?.cancel();
    _pruneTimer = Timer.periodic(const Duration(hours: 6), (_) => pruneOldTelemetry());
  }

  void stopPeriodicTasks() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
  }

  /// Appends sample to in-memory buffer. Flushes if buffer reaches capacity (30 samples).
  Future<void> bufferSample(TelemetrySample sample) async {
    _memoryBuffer.add(sample);
    if (_memoryBuffer.length >= maxBufferSize) {
      await flushBuffer();
    }
  }

  /// Flushes in-memory samples to disk in a single batched operation.
  Future<void> flushBuffer() async {
    if (_memoryBuffer.isEmpty || _telemetryFile == null) return;

    final toFlush = List<TelemetrySample>.from(_memoryBuffer);
    _memoryBuffer.clear();

    final buffer = StringBuffer();
    for (final s in toFlush) {
      buffer.writeln(jsonEncode(s.toMap()));
    }

    try {
      await _telemetryFile!.writeAsString(buffer.toString(), mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  /// Saves an anomaly incident to persistent storage immediately.
  Future<void> recordAnomaly(AnomalyIncident incident) async {
    if (_anomaliesFile == null) return;
    try {
      await _anomaliesFile!.writeAsString(
        '${jsonEncode(incident.toMap())}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  /// Prunes telemetry records older than 48 hours to conserve disk space.
  Future<void> pruneOldTelemetry() async {
    if (_telemetryFile == null || !await _telemetryFile!.exists()) return;

    try {
      final cutoff = DateTime.now().subtract(retentionPeriod);
      final lines = await _telemetryFile!.readAsLines();
      final retained = <String>[];

      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final map = jsonDecode(line) as Map<String, dynamic>;
          final timestamp = DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int);
          if (timestamp.isAfter(cutoff)) {
            retained.add(line);
          }
        } catch (_) {}
      }

      await _telemetryFile!.writeAsString(
        retained.isEmpty ? '' : '${retained.join('\n')}\n',
        flush: true,
      );
    } catch (_) {}
  }

  /// Retrieves recent telemetry samples for timeline visualization.
  Future<List<TelemetrySample>> getRecentTelemetry({int limit = 100}) async {
    final results = <TelemetrySample>[];
    results.addAll(_memoryBuffer);

    if (_telemetryFile != null && await _telemetryFile!.exists()) {
      try {
        final lines = await _telemetryFile!.readAsLines();
        for (final line in lines.reversed) {
          if (line.trim().isEmpty) continue;
          try {
            final map = jsonDecode(line) as Map<String, dynamic>;
            results.add(TelemetrySample.fromMap(map));
            if (results.length >= limit) break;
          } catch (_) {}
        }
      } catch (_) {}
    }

    results.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return results;
  }
}
