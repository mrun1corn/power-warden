import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/anomaly_engine.dart';
import '../domain/models/anomaly_incident.dart';
import '../domain/models/telemetry_sample.dart';
import '../services/notification_service.dart';
import '../services/telemetry_service.dart';
import 'theme.dart';
import 'widgets/anomaly_card.dart';
import 'widgets/current_gauge.dart';
import 'widgets/drain_timeline_chart.dart';
import 'widgets/metric_chips.dart';
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

  TelemetrySample? _currentSample;
  final List<TelemetrySample> _history = [];
  final List<AnomalyIncident> _incidents = [];

  StreamSubscription<TelemetrySample>? _streamSub;
  Map<String, bool> _elevatedStatus = {'hasShizuku': false, 'hasPermission': false, 'hasKadb': false};
  bool _isProMode = false;

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
    _elevatedStatus = await _telemetryService.getElevatedStatus();
    _currentSample = await _telemetryService.getInstantMetrics();
    await _telemetryService.startForegroundService();
    _loadProcesses();

    // Auto-refresh active energy consumers every 5 seconds
    _processRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _loadProcesses();
    });

    // Listen to live stream
    _streamSub = _telemetryService.telemetryStream.listen((sample) {
      setState(() {
        _currentSample = sample;
        _history.add(sample);
        if (_history.length > 60) _history.removeAt(0);

        final incident = _anomalyEngine.evaluateSample(sample);
        if (incident != null) {
          _incidents.insert(0, incident);
          _notificationService.showAnomalyNotification(incident);
        }
      });
    });

    if (mounted) setState(() {});
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
        hasPermission: _elevatedStatus['hasPermission'] ?? false,
        onAuthorized: () async {
          final s = await _telemetryService.getElevatedStatus();
          setState(() => _elevatedStatus = s);
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
          // Pro / Simple Mode Switcher
          TextButton.icon(
            onPressed: () => setState(() => _isProMode = !_isProMode),
            icon: Icon(
              _isProMode ? Icons.tune_rounded : Icons.auto_awesome_rounded,
              color: _isProMode ? AppTheme.chargingCyan : AppTheme.accentGreen,
              size: 16,
            ),
            label: Text(
              _isProMode ? 'PRO' : 'CALM',
              style: TextStyle(
                color: _isProMode ? AppTheme.chargingCyan : AppTheme.accentGreen,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.security_rounded,
              color: (_elevatedStatus['hasShizuku'] == true || _elevatedStatus['hasKadb'] == true)
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
                  if (!_isProMode) ...[
                    // --- CALM MINIMALIST VIEW ---
                    _buildCalmOverview(sample),
                    const SizedBox(height: 16),
                    _buildHumanDiagnosisCard(sample),
                    const SizedBox(height: 16),
                    _buildProcessUsageSection(),
                    const SizedBox(height: 16),
                  ] else ...[
                    // --- PRO DIAGNOSTICS VIEW ---
                    CurrentGauge(
                      currentMa: sample.currentMilliamps,
                      isCharging: sample.isCharging,
                    ),
                    const SizedBox(height: 12),
                    MetricChips(
                      batteryLevel: sample.batteryLevel,
                      isCharging: sample.isCharging,
                      temperatureCelsius: sample.temperatureCelsius,
                      voltageMv: sample.voltageMv,
                      isScreenOn: sample.isScreenOn,
                      hasElevatedAccess: _elevatedStatus['hasPermission'] == true,
                      elevatedBackend: (_elevatedStatus['hasPermission'] == true)
                          ? ElevatedBackendType.shizuku
                          : ElevatedBackendType.none,
                      onTapElevated: _showPairingModal,
                    ),
                    const SizedBox(height: 16),
                    DrainTimelineChart(samples: _history),
                    const SizedBox(height: 16),

                    // Top Active Processes / Resource Eaters Section
                    _buildProcessUsageSection(),
                    const SizedBox(height: 16),
                  ],

                  // Anomaly Incidents Section
                  Row(
                    children: [
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
                              await _telemetryService.remediateApp(incident.culpritPackage!);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Tamed ${incident.culpritPackage}')),
                                );
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
                final cpuTime = (proc['cpuTime'] as String?) ?? '';
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
                      if (cpuTime.isNotEmpty && cpuTime != '--:--')
                        Padding(
                          padding: const EdgeInsets.only(left: 4.0),
                          child: Text(
                            cpuTime,
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 9),
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
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16, color: AppTheme.textSecondary),
                        tooltip: 'Force Stop',
                        onPressed: () async {
                          await _telemetryService.remediateApp(pkg);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Tamed $name')),
                            );
                            _loadProcesses();
                          }
                        },
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

  /// Calm human-friendly hero overview
  Widget _buildCalmOverview(TelemetrySample sample) {
    final isCharging = sample.isCharging;
    final level = sample.batteryLevel;
    final hoursRemaining = isCharging ? 0.6 : (level * 0.22); // Estimator

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$level',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 72,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2.0,
                ),
              ),
              const Text(
                '%',
                style: TextStyle(
                  color: AppTheme.accentGreen,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isCharging
                ? '⚡ Fast Charging · Full in ~${(hoursRemaining * 60).round()} min'
                : '🔋 Healthy · About ${hoursRemaining.round()} hours left',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          // Clean progress bar
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

  /// Plain human diagnosis card
  Widget _buildHumanDiagnosisCard(TelemetrySample sample) {
    final absMa = sample.currentMilliamps.abs();
    final bool isHighDrain = !sample.isCharging && absMa > 450;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isHighDrain ? AppTheme.crimson.withOpacity(0.12) : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighDrain ? AppTheme.crimson.withOpacity(0.4) : AppTheme.surfaceBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isHighDrain ? Icons.warning_rounded : Icons.check_circle_rounded,
            color: isHighDrain ? AppTheme.crimson : AppTheme.accentGreen,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isHighDrain ? 'Drain Higher Than Normal' : 'Standby Drain is Low',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  isHighDrain
                      ? 'Phone is using $absMa mA right now. Tap PRO to trace culprit apps.'
                      : 'Display and apps sleeping soundly. Sentinel is monitoring.',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
