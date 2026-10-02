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

    // Listen to live stream
    _streamSub = _telemetryService.telemetryStream.listen((sample) {
      setState(() {
        _currentSample = sample;
        _history.add(sample);
        if (_history.length > 60) _history.removeAt(0);

        // Evaluate anomaly
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
    super.dispose();
  }

  void _showPairingModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WirelessPairingSheet(
        hasShizuku: _elevatedStatus['hasShizuku'] ?? false,
        hasKadb: _elevatedStatus['hasKadb'] ?? false,
        onRequestShizuku: () async {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Requesting Shizuku authorization...')),
          );
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
        title: const Row(
          children: [
            Icon(Icons.bolt, color: AppTheme.accentGreen, size: 24),
            SizedBox(width: 8),
            Text('PowerWarden'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.shield_outlined,
              color: (_elevatedStatus['hasShizuku'] == true || _elevatedStatus['hasKadb'] == true)
                  ? AppTheme.accentGreen
                  : AppTheme.amber,
            ),
            onPressed: _showPairingModal,
            tooltip: 'Elevated Diagnostics',
          ),
          const SizedBox(width: 8),
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
                  // Live Current Gauge with Neon Halo
                  CurrentGauge(
                    currentMa: sample.currentMilliamps,
                    isCharging: sample.isCharging,
                  ),
                  const SizedBox(height: 12),

                  // Metric Chips
                  MetricChips(
                    batteryLevel: sample.batteryLevel,
                    isCharging: sample.isCharging,
                    temperatureCelsius: sample.temperatureCelsius,
                    voltageMv: sample.voltageMv,
                    isScreenOn: sample.isScreenOn,
                    hasElevatedAccess: _elevatedStatus['hasShizuku'] == true || _elevatedStatus['hasKadb'] == true,
                    elevatedBackend: (_elevatedStatus['hasKadb'] == true)
                        ? ElevatedBackendType.kadb
                        : ((_elevatedStatus['hasShizuku'] == true)
                            ? ElevatedBackendType.shizuku
                            : ElevatedBackendType.none),
                    onTapElevated: _showPairingModal,
                  ),
                  const SizedBox(height: 16),

                  // Drain Timeline Chart
                  DrainTimelineChart(samples: _history),
                  const SizedBox(height: 20),

                  // Anomaly Incidents Section
                  Row(
                    children: [
                      const Text(
                        'ANOMALY INCIDENTS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_incidents.length} Detected',
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
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.surfaceBorder),
                      ),
                      child: const Center(
                        child: Text(
                          'No silent battery drain detected.\nSystem operating within normal baseline.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        ),
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
}
