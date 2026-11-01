import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/anomaly_incident.dart';
import '../../domain/models/power_session.dart';
import '../../domain/models/telemetry_sample.dart';

/// Read-only local persistence reader for PowerWarden.
///
/// **Ownership rule:** `PowerWardenService` (Kotlin) is the single writer for
/// every store — `telemetry_samples.jsonl`, `power_sessions.jsonl` and
/// `anomaly_incidents.jsonl`. This class only reads them, plus prunes expired
/// raw telemetry.
///
/// This split exists because the previous design had the Flutter dashboard and
/// the foreground service both appending to the same files, which duplicated
/// every session and every telemetry sample. Two writers, one file, no
/// coordination.
class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  File? _telemetryFile;
  File? _anomaliesFile;
  File? _sessionsFile;

  Timer? _pruneTimer;

  /// Raw telemetry ticks are retained for a week; sessions and incidents are
  /// kept indefinitely because they are the user-visible history.
  static const Duration retentionPeriod = Duration(days: 7);

  Future<void> initialize() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbDir = Directory(p.join(docsDir.path, 'power_warden_data'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    _telemetryFile = File(p.join(dbDir.path, 'telemetry_samples.jsonl'));
    _anomaliesFile = File(p.join(dbDir.path, 'anomaly_incidents.jsonl'));
    _sessionsFile = File(p.join(dbDir.path, 'power_sessions.jsonl'));

    startPeriodicTasks();
    await pruneOldTelemetry();
  }

  void startPeriodicTasks() {
    _pruneTimer?.cancel();
    _pruneTimer = Timer.periodic(
      const Duration(hours: 6),
      (_) => pruneOldTelemetry(),
    );
  }

  void stopPeriodicTasks() {
    _pruneTimer?.cancel();
    _pruneTimer = null;
  }

  /// Retrieves recorded historical power sessions, newest first.
  Future<List<PowerSession>> getRecentSessions({int limit = 40}) async {
    final results = <PowerSession>[];
    final file = _sessionsFile;
    if (file == null || !await file.exists()) return results;

    try {
      final lines = await file.readAsLines();
      for (final line in lines.reversed) {
        if (line.trim().isEmpty) continue;
        final session = _tryDecode(line, PowerSession.fromMap);
        if (session != null) {
          results.add(session);
          if (results.length >= limit) break;
        }
      }
    } catch (_) {
      // Unreadable store degrades to an empty history rather than a crash.
    }
    return results;
  }

  /// Retrieves recorded anomaly incidents, newest first.
  Future<List<AnomalyIncident>> getRecentAnomalies({int limit = 50}) async {
    final results = <AnomalyIncident>[];
    final file = _anomaliesFile;
    if (file == null || !await file.exists()) return results;

    try {
      final lines = await file.readAsLines();
      for (final line in lines.reversed) {
        if (line.trim().isEmpty) continue;
        final incident = _tryDecode(line, AnomalyIncident.fromMap);
        if (incident != null) {
          results.add(incident);
          if (results.length >= limit) break;
        }
      }
    } catch (_) {}
    return results;
  }

  /// Prunes raw telemetry ticks older than [retentionPeriod].
  ///
  /// Pruning is the only write this class performs, and it only ever *removes*
  /// records — it cannot duplicate a sample written by the service.
  Future<void> pruneOldTelemetry() async {
    final file = _telemetryFile;
    if (file == null || !await file.exists()) return;

    try {
      final cutoff = DateTime.now().subtract(retentionPeriod);
      final lines = await file.readAsLines();
      final retained = <String>[];

      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final map = jsonDecode(line) as Map<String, dynamic>;
          final timestamp = DateTime.fromMillisecondsSinceEpoch(
            map['timestamp'] as int,
          );
          if (timestamp.isAfter(cutoff)) retained.add(line);
        } catch (_) {
          // Drop corrupt lines rather than retaining them forever.
        }
      }

      await file.writeAsString(
        retained.isEmpty ? '' : '${retained.join('\n')}\n',
        flush: true,
      );
    } catch (_) {}
  }

  /// Retrieves the most recent telemetry samples, oldest first.
  Future<List<TelemetrySample>> getRecentTelemetry({int limit = 100}) async {
    final results = <TelemetrySample>[];
    final file = _telemetryFile;
    if (file == null || !await file.exists()) return results;

    try {
      final lines = await file.readAsLines();
      for (final line in lines.reversed) {
        if (line.trim().isEmpty) continue;
        final sample = _tryDecode(line, TelemetrySample.fromMap);
        if (sample != null) {
          results.add(sample);
          if (results.length >= limit) break;
        }
      }
    } catch (_) {}

    results.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return results;
  }

  /// Retrieves telemetry samples inside a session window, oldest first.
  ///
  /// Scans the whole store rather than a tail window so session detail charts
  /// stay populated after the recent-sample buffer has rolled over.
  Future<List<TelemetrySample>> getTelemetryForSession(
    DateTime startTime,
    DateTime endTime, {
    int limit = 200,
  }) async {
    final results = <TelemetrySample>[];
    final file = _telemetryFile;
    if (file == null || !await file.exists()) return results;

    try {
      final lines = await file.readAsLines();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final map = jsonDecode(line) as Map<String, dynamic>;
          final ts = DateTime.fromMillisecondsSinceEpoch(
            map['timestamp'] as int,
          );
          if (!ts.isBefore(startTime) && !ts.isAfter(endTime)) {
            results.add(TelemetrySample.fromMap(map));
            if (results.length >= limit) break;
          }
        } catch (_) {}
      }
    } catch (_) {}

    results.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return results;
  }

  /// Decodes one JSONL line, returning null for corrupt records instead of
  /// aborting the whole read — a single bad line used to silently truncate the
  /// entire history.
  T? _tryDecode<T>(String line, T Function(Map<String, dynamic>) fromMap) {
    try {
      final map = jsonDecode(line) as Map<String, dynamic>;
      return fromMap(map);
    } catch (_) {
      return null;
    }
  }
}
