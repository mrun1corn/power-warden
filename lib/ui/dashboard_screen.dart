import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/anomaly_engine.dart';
import '../domain/models/anomaly_incident.dart';
import '../domain/models/power_session.dart';
import '../domain/models/telemetry_sample.dart';
import '../data/database/database.dart';
import '../services/notification_service.dart';
import '../services/telemetry_service.dart';
import 'theme.dart';
import 'widgets/drain_timeline_chart.dart';
import 'widgets/wireless_pairing_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final TelemetryService _telemetryService = TelemetryService();
  final AnomalyEngine _anomalyEngine = AnomalyEngine();
  final NotificationService _notificationService = NotificationService();
  final AppDatabase _database = AppDatabase();

  TelemetrySample? _currentSample;
  final List<TelemetrySample> _history = [];
  final List<AnomalyIncident> _incidents = [];

  StreamSubscription<TelemetrySample>? _streamSub;
  Map<String, bool> _elevatedStatus = {
    'hasShizuku': false,
    'hasPermission': false,
    'hasKadb': false,
    'hasPermanentAdb': false,
    'hasAnyElevatedAccess': false,
  };

  List<Map<String, dynamic>> _topProcesses = [];
  bool _isLoadingProcesses = false;
  Timer? _processRefreshTimer;

  bool _dismissedNightStandby = false;

  // Session History Tracking
  DateTime? _sessionStartTime;
  int? _sessionStartLevel;
  bool? _sessionIsCharging;
  int _peakMaInSession = 0;
  double _peakWattsInSession = 0.0;
  double _minTempInSession = 99.0;
  double _maxTempInSession = 0.0;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await _notificationService.initialize();
    await _database.initialize();

    // Load saved historical samples and anomalies from disk
    final savedSamples = await _database.getRecentTelemetry(limit: 60);
    if (savedSamples.isNotEmpty) {
      _history.addAll(savedSamples);
    }

    final savedAnomalies = await _database.getRecentAnomalies(limit: 20);
    if (savedAnomalies.isNotEmpty) {
      _incidents.addAll(savedAnomalies);
    }

    _elevatedStatus = await _telemetryService.getElevatedStatus();
    _currentSample = await _telemetryService.getInstantMetrics();
    await _telemetryService.startForegroundService();
    _loadProcesses();

    // Auto-refresh active energy consumers and elevated state every 5 seconds
    _processRefreshTimer = Timer.periodic(const Duration(seconds: 5), (
      _,
    ) async {
      if (mounted) {
        _loadProcesses();
        final s = await _telemetryService.getElevatedStatus();
        if (s['hasAnyElevatedAccess'] !=
                _elevatedStatus['hasAnyElevatedAccess'] ||
            s['hasKadb'] != _elevatedStatus['hasKadb'] ||
            s['hasShizukuPermission'] !=
                _elevatedStatus['hasShizukuPermission']) {
          setState(() => _elevatedStatus = s);
        }
      }
    });

    // Listen to live stream
    _streamSub = _telemetryService.telemetryStream.listen((sample) {
      _processSessionTracking(sample);
      setState(() {
        _currentSample = sample;
        _history.add(sample);
        if (_history.length > 60) _history.removeAt(0);

        _database.bufferSample(sample);

        final incident = _anomalyEngine.evaluateSample(
          sample,
          topProcess: _topProcesses.isNotEmpty ? _topProcesses.first : null,
        );
        if (incident != null) {
          _incidents.insert(0, incident);
          _database.recordAnomaly(incident);

          // Trigger differential snapshotting if elevated access is active
          if (_elevatedStatus['hasAnyElevatedAccess'] == true) {
            _telemetryService.runDeltaDiagnostics();
          }

          if (_anomalyEngine.shouldAlertNotification(incident)) {
            final topApp = _topProcesses.isNotEmpty
                ? _topProcesses.first
                : null;
            final topName = topApp?['name'] as String?;
            final topCpu = (topApp?['cpuPercent'] as num?)?.toDouble();

            _notificationService.showAnomalyNotification(
              incident,
              topAppName: topName,
              topAppCpu: topCpu,
            );
          }
        }
      });
    });

    if (mounted) {
      setState(() {});
      _checkElevatedWarning();
    }
  }

  void _processSessionTracking(TelemetrySample sample) {
    final now = DateTime.now();
    final absMa = sample.currentMilliamps.abs();
    final watts = (sample.voltageMv / 1000.0) * (absMa / 1000.0);

    if (_sessionIsCharging == null) {
      _sessionIsCharging = sample.isCharging;
      _sessionStartTime = now;
      _sessionStartLevel = sample.batteryLevel;
      _peakMaInSession = absMa;
      _peakWattsInSession = watts;
      _minTempInSession = sample.temperatureCelsius;
      _maxTempInSession = sample.temperatureCelsius;
      return;
    }

    // Check if charging state changed (e.g. plugged in or unplugged)
    if (_sessionIsCharging != sample.isCharging) {
      final startTime =
          _sessionStartTime ?? now.subtract(const Duration(minutes: 1));
      final duration = now.difference(startTime);

      // Save valid charging or discharging sessions
      if (duration.inSeconds >= 10) {
        final startLvl = _sessionStartLevel ?? sample.batteryLevel;
        final deltaPercent = (sample.batteryLevel - startLvl).abs();
        final mahDelta = math.max(15, ((deltaPercent / 100.0) * 4500).round());
        final topApp = _topProcesses.isNotEmpty
            ? (_topProcesses.first['name'] as String? ?? '')
            : '';

        final session = PowerSession(
          id: now.millisecondsSinceEpoch.toString(),
          type: _sessionIsCharging! ? 'charging' : 'discharging',
          startTime: startTime,
          endTime: now,
          startBatteryLevel: startLvl,
          endBatteryLevel: sample.batteryLevel,
          totalMahDelta: mahDelta,
          peakMa: _peakMaInSession,
          peakWatts: _peakWattsInSession,
          minTempCelsius: _minTempInSession,
          maxTempCelsius: _maxTempInSession,
          topAppName: topApp,
        );

        _database.recordPowerSession(session);
      }

      // Reset for new session
      _sessionIsCharging = sample.isCharging;
      _sessionStartTime = now;
      _sessionStartLevel = sample.batteryLevel;
      _peakMaInSession = absMa;
      _peakWattsInSession = watts;
      _minTempInSession = sample.temperatureCelsius;
      _maxTempInSession = sample.temperatureCelsius;
    } else {
      // Accumulate peak stats
      if (absMa > _peakMaInSession) {
        _peakMaInSession = absMa;
      }
      if (watts > _peakWattsInSession) {
        _peakWattsInSession = watts;
      }
      if (sample.temperatureCelsius < _minTempInSession) {
        _minTempInSession = sample.temperatureCelsius;
      }
      if (sample.temperatureCelsius > _maxTempInSession) {
        _maxTempInSession = sample.temperatureCelsius;
      }
    }
  }

  Future<void> _checkElevatedWarning() async {
    // Suppressed: Using inline non-intrusive banner instead of modal dialog
    return;
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _processRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadProcesses() async {
    setState(() => _isLoadingProcesses = true);
    final procs = await _telemetryService.getRunningProcesses();
    if (mounted) {
      setState(() {
        _topProcesses = procs;
        _isLoadingProcesses = false;
      });
    }
  }

  void _confirmAndRemediate(String name, String pkg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: isDark
                  ? AppTheme.surfaceBorderDark
                  : AppTheme.surfaceBorderLight,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.surfaceBorderDark
                        : AppTheme.surfaceBorderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppTheme.crimson.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: AppTheme.crimson,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Force Stop $name?',
                          style: TextStyle(
                            color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          pkg,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark ? AppTheme.textMuted : AppTheme.textMutedLight,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'This will kill the app process and release its background CPU threads and wakelocks.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? Colors.white : Colors.black,
                        side: BorderSide(
                          color: isDark
                              ? AppTheme.surfaceBorderDark
                              : AppTheme.surfaceBorderLight,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final messenger = ScaffoldMessenger.of(context);
                        final ok = await _telemetryService.remediateApp(pkg);
                        if (!mounted) return;
                        if (ok) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('✓ Force-stopped $name'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                          _loadProcesses();
                        } else {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Please tap "Force Stop" in $name system settings',
                              ),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.crimson,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Force Stop',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPairingModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WirelessPairingSheet(
        hasShizuku: _elevatedStatus['hasShizuku'] ?? false,
        hasPermission: _elevatedStatus['hasShizukuPermission'] ?? false,
        hasKadb: _elevatedStatus['hasKadb'] ?? false,
        onAuthorized: () async {
          final s = await _telemetryService.getElevatedStatus();
          if (mounted) {
            setState(() => _elevatedStatus = s);
            Navigator.pop(context); // Close sheet automatically upon success!
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sample = _currentSample;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? AppTheme.pureOledBackground
        : AppTheme.lightBackground;
    final surfaceColor = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final surfaceBorder = isDark
        ? AppTheme.surfaceBorderDark
        : AppTheme.surfaceBorderLight;
    final textColor = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textMuted = isDark ? AppTheme.textMuted : AppTheme.textMutedLight;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: scaffoldBg,
        title: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppTheme.accentGreen,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'PowerWarden',
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          // Only show pairing warning icon if elevated access is NOT granted yet
          if (_elevatedStatus['hasAnyElevatedAccess'] != true)
            IconButton(
              icon: const Icon(
                Icons.shield_outlined,
                color: AppTheme.amber,
                size: 20,
              ),
              onPressed: _showPairingModal,
              tooltip: 'Set Up Permissions',
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: sample == null
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accentGreen),
            )
          : RefreshIndicator(
              onRefresh: () async {
                final s = await _telemetryService.getInstantMetrics();
                await _loadProcesses();
                final elevated = await _telemetryService.getElevatedStatus();
                if (mounted) {
                  setState(() {
                    _currentSample = s;
                    _elevatedStatus = elevated;
                  });
                }
              },
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                children: [
                  // Feature 2: Sleep Sentinel Night Standby Card (Shown if phone woke up after resting)
                  if (!_dismissedNightStandby &&
                      (sample.sleepDurationMs > (1000 * 60 * 30))) ...[
                    _buildNightStandbyCard(sample),
                    const SizedBox(height: 12),
                  ],

                  // Inline Non-Intrusive Privilege Banner (shown only when unprivileged)
                  if (_elevatedStatus['hasAnyElevatedAccess'] != true) ...[
                    _buildInlinePrivilegeBanner(),
                    const SizedBox(height: 12),
                  ],

                  // Unified Minimal Command Card (Battery Status + Instant Telemetry Strip)
                  _buildUnifiedCommandCard(
                    sample,
                    surfaceColor,
                    surfaceBorder,
                    textColor,
                    textMuted,
                  ),
                  const SizedBox(height: 16),

                  // Discharge Timeline
                  DrainTimelineChart(samples: _history),
                  const SizedBox(height: 16),

                  // Active Process Consumption Section
                  _buildProcessUsageSection(
                    surfaceColor,
                    surfaceBorder,
                    textColor,
                    textMuted,
                  ),
                  SizedBox(
                    height: MediaQuery.viewPaddingOf(context).bottom + 24,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInlinePrivilegeBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.amber.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppTheme.amber.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: AppTheme.amber,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Baseline Sensor Mode Active',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Link Shizuku or Wireless ADB for deep thread inspection & 1-tap kill.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _showPairingModal,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.amber,
              foregroundColor: Colors.black,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(60, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Pair',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNightStandbyCard(TelemetrySample sample) {
    final hoursAsleep = (sample.sleepDurationMs / (1000.0 * 60 * 60))
        .toStringAsFixed(1);
    final idleBurnRate = ((sample.currentMilliamps.abs() / 4500.0) * 100.0)
        .toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.chargingCyan.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.chargingCyan.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.nightlight_round,
              color: AppTheme.chargingCyan,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sleep Standby Summary',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Rested for ${hoursAsleep}h • Average burn: ~$idleBurnRate%/hr',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              size: 16,
              color: AppTheme.textMuted,
            ),
            onPressed: () => setState(() => _dismissedNightStandby = true),
          ),
        ],
      ),
    );
  }

  /// App resource and energy drainers list
  Widget _buildProcessUsageSection(
    Color surfaceColor,
    Color surfaceBorder,
    Color textColor,
    Color textMuted,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.apps_rounded, size: 16, color: textMuted),
            const SizedBox(width: 6),
            Text(
              'ACTIVE APP ENERGY CONSUMPTION',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                color: textMuted,
              ),
            ),
            const Spacer(),
            if (_isLoadingProcesses)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.accentGreen,
                ),
              )
            else
              InkWell(
                onTap: _loadProcesses,
                child: const Text(
                  'Refresh',
                  style: TextStyle(
                    color: AppTheme.chargingCyan,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_topProcesses.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: surfaceBorder),
            ),
            child: Center(
              child: Text(
                'No heavy apps consuming active CPU cycles.\nTap refresh or authorize Shizuku for deep inspection.',
                textAlign: TextAlign.center,
                style: TextStyle(color: textMuted, fontSize: 12),
              ),
            ),
          )
        else
          Column(
            children: _topProcesses.map((proc) {
              final name = (proc['name'] as String?) ?? 'App';
              final pkg = (proc['packageName'] as String?) ?? '';
              final cpu = (proc['cpuPercent'] as num?)?.toDouble() ?? 0.0;
              final ramMb = (proc['ramMb'] as num?)?.toInt() ?? 0;
              final isHeavy = cpu > 10.0;
              final isCriticalCpu = cpu > 25.0;

              // AOSP Power Profile Model for realistic lower-bound app drain detection:
              // Isolate display baseline (~240-280mA) and radio baseline (~40mA) so app mA is never falsely inflated.
              final totalMa = (_currentSample?.currentMilliamps.abs() ?? 450);
              final isScreenOn = _currentSample?.isScreenOn ?? true;
              final screenBaseline = isScreenOn
                  ? math.min(totalMa * 0.55, 260.0)
                  : 0.0;
              final radioBaseline = isScreenOn ? 40.0 : 15.0;
              final processPool = math.max(
                25.0,
                totalMa - screenBaseline - radioBaseline,
              );

              final totalAppCpu = _topProcesses
                  .fold<double>(
                    0.0,
                    (acc, p) =>
                        acc + ((p['cpuPercent'] as num?)?.toDouble() ?? 0.0),
                  )
                  .clamp(1.0, 100.0);
              final appEstimatedMa = math.max(
                2,
                (processPool * (cpu / totalAppCpu)).round(),
              );

              final isDark = Theme.of(context).brightness == Brightness.dark;
              final cardBg = isDark
                  ? (isCriticalCpu
                        ? AppTheme.crimson.withValues(alpha: 0.08)
                        : (isHeavy
                              ? AppTheme.amber.withValues(alpha: 0.05)
                              : AppTheme.surfaceVariantDark.withValues(
                                  alpha: 0.5,
                                )))
                  : (isCriticalCpu
                        ? AppTheme.crimson.withValues(alpha: 0.08)
                        : (isHeavy
                              ? AppTheme.amber.withValues(alpha: 0.06)
                              : AppTheme.surfaceLight));

              final cardBorder = isDark
                  ? (isHeavy
                        ? (isCriticalCpu
                              ? AppTheme.crimson.withValues(alpha: 0.4)
                              : AppTheme.amber.withValues(alpha: 0.3))
                        : AppTheme.surfaceBorderDark.withValues(alpha: 0.6))
                  : (isHeavy
                        ? (isCriticalCpu
                              ? AppTheme.crimson.withValues(alpha: 0.4)
                              : AppTheme.amber.withValues(alpha: 0.4))
                        : AppTheme.surfaceBorderLight);

              final titleColor = isDark
                  ? Colors.white
                  : AppTheme.textPrimaryLight;
              final subtitleColor = isDark
                  ? AppTheme.textMuted
                  : AppTheme.textMutedLight;

              final stateColor = isHeavy
                  ? (isCriticalCpu ? AppTheme.crimson : AppTheme.amber)
                  : AppTheme.accentGreen;
              final stateLabel = isCriticalCpu
                  ? 'CRITICAL'
                  : (isHeavy ? 'HEAVY' : 'CALM');

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cardBorder, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row: App Icon + Name + Symmetrical Action Group ([STATUS] [STOP])
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: isHeavy
                                ? stateColor.withValues(alpha: 0.15)
                                : (isDark
                                      ? AppTheme.surfaceVariantDark
                                      : AppTheme.surfaceVariantLight),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isHeavy
                                ? Icons.bolt_rounded
                                : Icons.android_rounded,
                            size: 15,
                            color: isHeavy
                                ? stateColor
                                : (isDark
                                      ? AppTheme.textSecondary
                                      : AppTheme.textSecondaryLight),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  color: titleColor,
                                  fontWeight: isHeavy
                                      ? FontWeight.w800
                                      : FontWeight.bold,
                                  fontSize: 13,
                                  height: 1.2,
                                ),
                                softWrap: true,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                pkg,
                                style: TextStyle(
                                  color: subtitleColor,
                                  fontSize: 9.5,
                                  fontFamily: 'monospace',
                                ),
                                maxLines: 2,
                                softWrap: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Symmetrical Button Cluster: [STATUS] & [STOP] with identical height and border radius
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // State Indicator Button
                            Container(
                              height: 26,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: stateColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: stateColor.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                stateLabel,
                                style: TextStyle(
                                  color: stateColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),

                            // Force Stop Action Button (48dp interactive touch target)
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _confirmAndRemediate(name, pkg),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 48,
                                    minWidth: 54,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isHeavy
                                        ? (isDark
                                              ? AppTheme.crimson.withValues(
                                                  alpha: 0.15,
                                                )
                                              : AppTheme.crimsonLight
                                                    .withValues(alpha: 0.12))
                                        : (isDark
                                              ? AppTheme.surfaceVariantDark
                                              : AppTheme.surfaceVariantLight),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isHeavy
                                          ? (isDark
                                                    ? AppTheme.crimson
                                                    : AppTheme.crimsonLight)
                                                .withValues(alpha: 0.4)
                                          : (isDark
                                                ? AppTheme.surfaceBorderDark
                                                : AppTheme.surfaceBorderLight),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    'STOP',
                                    style: TextStyle(
                                      color: isHeavy
                                          ? (isDark
                                                ? AppTheme.crimson
                                                : AppTheme.crimsonLight)
                                          : (isDark
                                                ? AppTheme.textSecondary
                                                : AppTheme.textSecondaryLight),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Metrics Ribbon: Estimated mA, CPU %, and RAM MB
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppTheme.surfaceVariantDark
                                : AppTheme.surfaceVariantLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.flash_on_rounded,
                                size: 12,
                                color: AppTheme.chargingCyan,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '~$appEstimatedMa mA',
                                style: const TextStyle(
                                  color: AppTheme.chargingCyan,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${cpu.toStringAsFixed(1)}% CPU',
                          style: TextStyle(
                            color: isHeavy
                                ? stateColor
                                : (isDark
                                      ? AppTheme.textSecondary
                                      : AppTheme.textSecondaryLight),
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                        if (ramMb > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '•   ${ramMb}MB RAM',
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildUnifiedCommandCard(
    TelemetrySample sample,
    Color surfaceColor,
    Color surfaceBorder,
    Color textColor,
    Color textMuted,
  ) {
    final isCharging = sample.isCharging;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final level = sample.batteryLevel;
    final absMa = sample.currentMilliamps.abs();
    final bool isScreenOn = sample.isScreenOn;

    // Dynamic hours left and hourly burn velocity
    final double hoursRemaining;
    if (isCharging) {
      final neededMah = ((100 - level) / 100.0) * 4500.0;
      hoursRemaining = math.max(0.1, neededMah / math.max(absMa.toDouble(), 400.0));
    } else {
      final remainingMah = (level / 100.0) * 4500.0;
      hoursRemaining = math.max(0.5, remainingMah / math.max(absMa.toDouble(), 180.0));
    }
    final burnRatePerHour = ((absMa / 4500.0) * 100.0).toStringAsFixed(1);

    final Color statusColor;
    final String statusBadge;
    if (isCharging) {
      statusColor = isDark ? AppTheme.chargingCyan : AppTheme.chargingCyanLight;
      statusBadge = 'CHARGING';
    } else if (!isScreenOn) {
      // Standby / Screen-off thresholds
      if (absMa > 350) {
        statusColor = isDark ? AppTheme.crimson : AppTheme.crimsonLight;
        statusBadge = 'WAKELOCK DRAIN';
      } else if (absMa > 150) {
        statusColor = isDark ? AppTheme.amber : AppTheme.amberLight;
        statusBadge = 'SLEEP LEAK';
      } else {
        statusColor = isDark ? AppTheme.accentGreen : AppTheme.accentGreenLight;
        statusBadge = 'DEEP SLEEP';
      }
    } else {
      // Screen ON active display (nominal 400-900mA for 120Hz LTPO panels)
      if (absMa > 1400 || (absMa > 1200 && sample.temperatureCelsius >= 40.0)) {
        statusColor = isDark ? AppTheme.crimson : AppTheme.crimsonLight;
        statusBadge = 'CRITICAL DRAIN';
      } else if (absMa > 950) {
        statusColor = isDark ? AppTheme.amber : AppTheme.amberLight;
        statusBadge = 'HEAVY LOAD';
      } else {
        statusColor = isDark ? AppTheme.accentGreen : AppTheme.accentGreenLight;
        statusBadge = 'NOMINAL';
      }
    }

    final volts = (sample.voltageMv / 1000.0).toStringAsFixed(2);
    final watts = ((sample.voltageMv / 1000.0) * (absMa / 1000.0))
        .toStringAsFixed(1);
    final currentLabel = isCharging ? '+$absMa mA' : '-$absMa mA';
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Upper Level: Battery % + Burn Velocity + Health Row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$level%',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.5,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            currentLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: statusColor.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              statusBadge,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            isCharging
                                ? Icons.battery_charging_full_rounded
                                : Icons.battery_std_rounded,
                            size: 15,
                            color: statusColor,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isCharging
                                ? 'Fast Charging · Full in ~${(hoursRemaining * 60).round()}m'
                                : 'Battery Healthy · ~${hoursRemaining.toStringAsFixed(1)}h left (~$burnRatePerHour%/hr)',
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_elevatedStatus['hasAnyElevatedAccess'] != true)
                  InkWell(
                    onTap: _showPairingModal,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.amber.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.link_rounded,
                            size: 14,
                            color: AppTheme.amber,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'SET UP',
                            style: TextStyle(
                              color: AppTheme.amber,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Divider between Hero and Telemetry Strip
          Divider(height: 1, color: surfaceBorder),

          // Lower Level: Integrated Telemetry Strip (CURRENT, POWER, TEMP, VOLTS)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildRibbonItem(
                  icon: Icons.speed_rounded,
                  color: isCharging ? AppTheme.chargingCyan : statusColor,
                  label: isCharging ? 'CHARGE' : 'CURRENT',
                  value: currentLabel,
                ),
                Container(width: 1, height: 26, color: surfaceBorder),
                _buildRibbonItem(
                  icon: Icons.bolt_rounded,
                  color: isCharging ? AppTheme.chargingCyan : AppTheme.amber,
                  label: 'POWER',
                  value: '${watts}W',
                ),
                Container(width: 1, height: 26, color: surfaceBorder),
                _buildRibbonItem(
                  icon: Icons.thermostat_rounded,
                  color: sample.temperatureCelsius >= 38.0
                      ? AppTheme.amber
                      : AppTheme.accentGreen,
                  label: 'TEMP',
                  value: '${sample.temperatureCelsius.toStringAsFixed(1)}°C',
                ),
                Container(width: 1, height: 26, color: surfaceBorder),
                _buildRibbonItem(
                  icon: Icons.battery_charging_full_rounded,
                  color: textMuted,
                  label: 'VOLTS',
                  value: '${volts}V',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRibbonItem({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
