import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/anomaly_engine.dart';
import '../domain/models/anomaly_incident.dart';
import '../domain/models/telemetry_sample.dart';
import '../data/database/database.dart';
import '../services/notification_service.dart';
import '../services/telemetry_service.dart';
import 'theme.dart';
import 'widgets/anomaly_card.dart';
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
  Map<String, bool> _elevatedStatus = {'hasShizuku': false, 'hasPermission': false, 'hasKadb': false};

  List<Map<String, dynamic>> _topProcesses = [];
  bool _isLoadingProcesses = false;
  Timer? _processRefreshTimer;

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
    _processRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (mounted) {
        _loadProcesses();
        final s = await _telemetryService.getElevatedStatus();
        if (s['hasAnyElevatedAccess'] != _elevatedStatus['hasAnyElevatedAccess'] ||
            s['hasKadb'] != _elevatedStatus['hasKadb'] ||
            s['hasShizukuPermission'] != _elevatedStatus['hasShizukuPermission']) {
          setState(() => _elevatedStatus = s);
        }
      }
    });

    // Listen to live stream
    _streamSub = _telemetryService.telemetryStream.listen((sample) {
      setState(() {
        _currentSample = sample;
        _history.add(sample);
        if (_history.length > 60) _history.removeAt(0);

        _database.bufferSample(sample);

        final incident = _anomalyEngine.evaluateSample(sample);
        if (incident != null) {
          _incidents.insert(0, incident);
          _database.recordAnomaly(incident);

          if (_anomalyEngine.shouldAlertNotification(incident)) {
            final topApp = _topProcesses.isNotEmpty ? _topProcesses.first : null;
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

  Future<void> _checkElevatedWarning() async {
    // Never show warning popup if user already has elevated access or permanent ADB granted!
    if (_elevatedStatus['hasAnyElevatedAccess'] == true) return;

    final hasPrompted = await _telemetryService.getPrefBool('has_prompted_unpaired_warning', defaultValue: false);
    if (!hasPrompted && mounted) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      _showUnpairedWarningDialog();
    }
  }

  void _showUnpairedWarningDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppTheme.amber.withOpacity(0.4), width: 1),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.amber.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded, color: AppTheme.amber, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Privileges Needed',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'PowerWarden is currently running in baseline mode.\n\nWithout Shizuku or Wireless ADB pairing, Android prevents the app from identifying other background processes or force-stopping runaway battery drains.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await _telemetryService.setPrefBool('has_prompted_unpaired_warning', true);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Remind Later', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              await _telemetryService.setPrefBool('has_prompted_unpaired_warning', true);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                _showPairingModal();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.amber,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Pair Now', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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

    return Scaffold(
      backgroundColor: AppTheme.pureOledBackground,
      appBar: AppBar(
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
            const Text('PowerWarden'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _elevatedStatus['hasAnyElevatedAccess'] == true
                  ? Icons.verified_user_rounded
                  : Icons.shield_outlined,
              color: _elevatedStatus['hasAnyElevatedAccess'] == true
                  ? AppTheme.accentGreen
                  : AppTheme.amber,
              size: 20,
            ),
            onPressed: _showPairingModal,
            tooltip: 'Deep Diagnostics',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: sample == null
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentGreen))
          : RefreshIndicator(
              onRefresh: () async {
                final s = await _telemetryService.getInstantMetrics();
                setState(() => _currentSample = s);
              },
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                children: [
                  // Battery Guru Hero Card
                  _buildBatteryGuruHeroCard(sample),
                  const SizedBox(height: 12),

                  // 3-Metric Clean Telemetry Ribbon (Current mA, Temp °C, Voltage V)
                  _buildTelemetryRibbon(sample),
                  const SizedBox(height: 16),

                  // Discharge Timeline
                  DrainTimelineChart(samples: _history),
                  const SizedBox(height: 16),

                  // Active Process Consumption Section
                  _buildProcessUsageSection(),
                  const SizedBox(height: 16),

                  // Sentinel Log Header with Clear All Action
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.accentGreen.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.history_rounded, size: 14, color: AppTheme.accentGreen),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'SENTINEL LOG',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      if (_incidents.isNotEmpty)
                        InkWell(
                          onTap: () {
                            setState(() => _incidents.clear());
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Text(
                              'Clear History',
                              style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                            ),
                          ),
                        )
                      else
                        Text(
                          '${_incidents.length} Events',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_incidents.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.surfaceBorder),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.accentGreen.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.shield_outlined, color: AppTheme.accentGreen, size: 22),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Everything Calm & Healthy',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'No background loops or battery vampires detected.',
                                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._incidents.map((incident) => AnomalyCard(
                          incident: incident,
                          onRemediate: () async {
                            if (incident.culpritPackage != null) {
                              final ok = await _telemetryService.remediateApp(incident.culpritPackage!);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(ok
                                        ? '✓ Force-stopped ${incident.culpritPackage}'
                                        : 'Could not stop ${incident.culpritPackage} (requires Shizuku or Wireless ADB)'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                                setState(() {
                                  final idx = _incidents.indexOf(incident);
                                  if (idx != -1) {
                                    _incidents[idx] = incident.copyWith(isRemediated: true);
                                  }
                                });
                              }
                            }
                          },
                        )),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  /// App resource and energy drainers list
  Widget _buildProcessUsageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.apps_rounded, size: 16, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            const Text(
              'ACTIVE APP ENERGY CONSUMPTION',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                color: AppTheme.textSecondary,
              ),
            ),
            const Spacer(),
            if (_isLoadingProcesses)
              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentGreen))
            else
              InkWell(
                onTap: _loadProcesses,
                child: const Text('Refresh', style: TextStyle(color: AppTheme.chargingCyan, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_topProcesses.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.surfaceBorder),
            ),
            child: const Center(
              child: Text(
                'No heavy apps consuming active CPU cycles.\nTap refresh or authorize Shizuku for deep inspection.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.surfaceBorder),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _topProcesses.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: AppTheme.surfaceBorder.withOpacity(0.5)),
              itemBuilder: (context, idx) {
                final proc = _topProcesses[idx];
                final name = (proc['name'] as String?) ?? 'App';
                final pkg = (proc['packageName'] as String?) ?? '';
                final cpu = (proc['cpuPercent'] as num?)?.toDouble() ?? 0.0;
                final ramMb = (proc['ramMb'] as num?)?.toInt() ?? 0;
                final isHeavy = cpu > 10.0;

                return ListTile(
                  dense: true,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isHeavy ? AppTheme.crimson.withOpacity(0.15) : AppTheme.surfaceVariant,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.android_rounded,
                      size: 16,
                      color: isHeavy ? AppTheme.crimson : AppTheme.textSecondary,
                    ),
                  ),
                  title: Row(
   children: [
     Expanded(
       child: Text(
         name.toUpperCase(),
         style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
         overflow: TextOverflow.ellipsis,
       ),
     ),
     if (ramMb > 0)
       Container(
         padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
         margin: const EdgeInsets.only(left: 6),
         decoration: BoxDecoration(
           color: AppTheme.surfaceVariant,
           borderRadius: BorderRadius.circular(4),
         ),
         child: Text(
           '${ramMb}MB RAM',
           style: const TextStyle(color: AppTheme.textSecondary, fontSize: 9, fontWeight: FontWeight.w600),
         ),
       ),
     Container(
       padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
       margin: const EdgeInsets.only(left: 6),
       decoration: BoxDecoration(
         color: isHeavy ? AppTheme.crimson.withOpacity(0.15) : AppTheme.accentGreen.withOpacity(0.12),
         borderRadius: BorderRadius.circular(4),
       ),
       child: Text(
         isHeavy ? 'Heavy' : 'Calm',
         style: TextStyle(
           color: isHeavy ? AppTheme.crimson : AppTheme.accentGreen,
           fontSize: 9,
           fontWeight: FontWeight.bold,
         ),
       ),
     ),
   ],
 ),
                  subtitle: Text(
                    pkg,
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isHeavy ? AppTheme.crimson.withOpacity(0.2) : AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${cpu.toStringAsFixed(1)}% CPU',
                          style: TextStyle(
                            color: isHeavy ? AppTheme.crimson : AppTheme.accentGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () async {
                          final ok = await _telemetryService.remediateApp(pkg);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok ? '✓ Force-stopped $name' : 'Could not stop $name (requires Shizuku or Wireless ADB)'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                            _loadProcesses();
                          }
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.crimson.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.crimson.withOpacity(0.3)),
                          ),
                          child: const Text(
                            'STOP',
                            style: TextStyle(
                              color: AppTheme.crimson,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildBatteryGuruHeroCard(TelemetrySample sample) {
    final isCharging = sample.isCharging;
    final level = sample.batteryLevel;
    final absMa = sample.currentMilliamps.abs();
    final hoursRemaining = isCharging ? 0.8 : (level * 0.22);

    final statusColor = isCharging
        ? AppTheme.chargingCyan
        : (absMa > 850
            ? AppTheme.crimson
            : (absMa > 650 ? AppTheme.amber : AppTheme.accentGreen));

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                          '$level',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 56,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.5,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '%',
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isCharging
                          ? '⚡ Fast Charging · Full in ~${(hoursRemaining * 60).round()}m'
                          : '🔋 Battery Healthy · ~${hoursRemaining.toStringAsFixed(1)}h remaining',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: _showPairingModal,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (_elevatedStatus['hasAnyElevatedAccess'] == true)
                        ? AppTheme.accentGreen.withOpacity(0.12)
                        : AppTheme.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (_elevatedStatus['hasAnyElevatedAccess'] == true)
                          ? AppTheme.accentGreen.withOpacity(0.3)
                          : AppTheme.amber.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        (_elevatedStatus['hasAnyElevatedAccess'] == true)
                            ? Icons.verified_user_rounded
                            : Icons.link_rounded,
                        size: 14,
                        color: (_elevatedStatus['hasAnyElevatedAccess'] == true)
                            ? AppTheme.accentGreen
                            : AppTheme.amber,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        (_elevatedStatus['hasPermanentAdb'] == true)
                            ? 'ADB GRANTED'
                            : ((_elevatedStatus['hasKadb'] == true)
                                ? 'KADB'
                                : ((_elevatedStatus['hasShizukuPermission'] == true) ? 'SHIZUKU' : 'UNPAIRED')),
                        style: TextStyle(
                          color: (_elevatedStatus['hasAnyElevatedAccess'] == true)
                              ? AppTheme.accentGreen
                              : AppTheme.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: level / 100.0,
              minHeight: 8,
              backgroundColor: AppTheme.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                isCharging
                    ? AppTheme.chargingCyan
                    : (level <= 20 ? AppTheme.crimson : AppTheme.accentGreen),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryRibbon(TelemetrySample sample) {
    final absMa = sample.currentMilliamps.abs();
    final isCharging = sample.isCharging;
    final volts = (sample.voltageMv / 1000.0).toStringAsFixed(2);

    final currentLabel = isCharging ? '+$absMa mA' : '-$absMa mA';
    final currentColor = isCharging
        ? AppTheme.chargingCyan
        : (absMa > 850 ? AppTheme.crimson : (absMa > 650 ? AppTheme.amber : AppTheme.chargingCyan));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildRibbonItem(
            icon: Icons.speed_rounded,
            color: currentColor,
            label: 'CURRENT',
            value: currentLabel,
          ),
          Container(width: 1, height: 32, color: AppTheme.surfaceBorder),
          _buildRibbonItem(
            icon: Icons.thermostat_rounded,
            color: sample.temperatureCelsius >= 38.0 ? AppTheme.amber : AppTheme.accentGreen,
            label: 'TEMP',
            value: '${sample.temperatureCelsius.toStringAsFixed(1)}°C',
          ),
          Container(width: 1, height: 32, color: AppTheme.surfaceBorder),
          _buildRibbonItem(
            icon: Icons.electric_bolt_rounded,
            color: AppTheme.amber,
            label: 'VOLTAGE',
            value: '${volts}V',
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
