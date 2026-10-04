import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../data/database/database.dart';
import '../../domain/models/power_session.dart';
import '../../domain/models/telemetry_sample.dart';
import '../../services/telemetry_service.dart';
import 'theme.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  final AppDatabase _database = AppDatabase();
  final TelemetryService _telemetryService = TelemetryService();

  late TabController _tabController;

  List<PowerSession> _allSessions = [];
  List<Map<String, dynamic>> _appUsageList = [];
  List<TelemetrySample> _historicalSamples = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllHistory() async {
    setState(() => _isLoading = true);
    await _database.initialize();
    final sessions = await _database.getRecentSessions(limit: 60);
    final appUsage = await _telemetryService.getHistoricalAppUsage(days: 1);
    final samples = await _database.getRecentTelemetry(limit: 120);

    if (mounted) {
      setState(() {
        _allSessions = sessions;
        _appUsageList = appUsage;
        _historicalSamples = samples;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final surfaceVariant = isDark ? AppTheme.surfaceVariantDark : AppTheme.surfaceVariantLight;
    final surfaceBorder = isDark ? AppTheme.surfaceBorderDark : AppTheme.surfaceBorderLight;
    final textColor = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textMuted = isDark ? AppTheme.textMuted : AppTheme.textMutedLight;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.pureOledBackground : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.pureOledBackground : AppTheme.lightBackground,
        title: Text(
          'Power History',
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false, // Clean equal distribution across screen width (no cutoffs)
          labelColor: AppTheme.accentGreen,
          unselectedLabelColor: textMuted,
          indicatorColor: AppTheme.accentGreen,
          indicatorWeight: 3,
          labelPadding: EdgeInsets.zero,
          tabs: const [
            Tab(icon: Icon(Icons.flash_on_rounded, size: 18), text: 'Charge'),
            Tab(icon: Icon(Icons.battery_alert_rounded, size: 18), text: 'Drain'),
            Tab(icon: Icon(Icons.apps_rounded, size: 18), text: 'Apps'),
            Tab(icon: Icon(Icons.nightlight_round, size: 18), text: 'Standby'),
          ],
        ),
        actions: [
          // OEM Battery Optimization Exemption Action
          IconButton(
            icon: const Icon(Icons.battery_charging_full_rounded, size: 20),
            tooltip: 'Disable Battery Optimization (Don\'t Kill My App)',
            onPressed: () async {
              final ok = await _telemetryService.requestIgnoreBatteryOptimizations();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Prompted battery optimization & OEM background autostart'
                        : 'Battery optimization settings could not be opened'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadAllHistory,
            tooltip: 'Refresh History',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Charging Sessions
                _buildSessionList(
                  _allSessions.where((s) => s.isCharging).toList(),
                  surfaceColor,
                  surfaceVariant,
                  surfaceBorder,
                  textColor,
                  textMuted,
                  isChargingTab: true,
                ),

                // Tab 2: Discharging Sessions
                _buildSessionList(
                  _allSessions.where((s) => !s.isCharging).toList(),
                  surfaceColor,
                  surfaceVariant,
                  surfaceBorder,
                  textColor,
                  textMuted,
                  isChargingTab: false,
                ),

                // Tab 3: App Usage History
                _buildAppUsageTab(surfaceColor, surfaceVariant, surfaceBorder, textColor, textMuted, isDark),

                // Tab 4: Standby Overnight History
                _buildStandbyTab(surfaceColor, surfaceVariant, surfaceBorder, textColor, textMuted, isDark),
              ],
            ),
    );
  }

  Widget _buildSessionList(
    List<PowerSession> sessions,
    Color surfaceColor,
    Color surfaceVariant,
    Color surfaceBorder,
    Color textColor,
    Color textMuted, {
    required bool isChargingTab,
  }) {
    // Fallback: If no sessions recorded yet, reconstruct session from recent historical samples
    final effectiveSessions = List<PowerSession>.from(sessions);
    if (effectiveSessions.isEmpty && _historicalSamples.isNotEmpty) {
      final matchingSamples = _historicalSamples.where((s) => isChargingTab ? s.isCharging : !s.isCharging).toList();
      if (matchingSamples.length >= 2) {
        final first = matchingSamples.last;
        final last = matchingSamples.first;
        final delta = (last.batteryLevel - first.batteryLevel).abs();
        final maxCur = matchingSamples.map((s) => s.currentMilliamps.abs()).reduce(math.max);
        final minT = matchingSamples.map((s) => s.temperatureCelsius).reduce(math.min);
        final maxT = matchingSamples.map((s) => s.temperatureCelsius).reduce(math.max);

        effectiveSessions.add(
          PowerSession(
            id: 'synthesized_recent',
            type: isChargingTab ? 'charging' : 'discharging',
            startTime: first.timestamp,
            endTime: last.timestamp,
            startBatteryLevel: first.batteryLevel,
            endBatteryLevel: last.batteryLevel,
            totalMahDelta: math.max(10, ((delta / 100.0) * 4500).round()),
            peakMa: maxCur,
            peakWatts: (last.voltageMv / 1000.0) * (maxCur / 1000.0),
            minTempCelsius: minT,
            maxTempCelsius: maxT,
            topAppName: _appUsageList.isNotEmpty ? (_appUsageList.first['name'] as String? ?? '') : '',
          ),
        );
      }
    }

    if (effectiveSessions.isEmpty) {
      return _buildEmptyState(
        icon: isChargingTab ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded,
        title: isChargingTab ? 'No charging sessions recorded yet' : 'No discharge cycles recorded yet',
        subtitle: isChargingTab
            ? 'Connect your phone to power to log charging speed, power (W), and battery health.'
            : 'Use your device on battery power to log discharge cycles and drain rates.',
        textColor: textColor,
        textMuted: textMuted,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: effectiveSessions.length,
      itemBuilder: (context, index) {
        final session = effectiveSessions[index];
        final accentColor = session.isCharging ? AppTheme.chargingCyan : AppTheme.accentGreen;
        final sign = session.isCharging ? '+' : '-';
        final deltaPercent = (session.endBatteryLevel - session.startBatteryLevel).abs();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      session.isCharging ? Icons.flash_on_rounded : Icons.battery_charging_full_rounded,
                      color: accentColor,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.isCharging ? 'Charge Cycle' : 'Discharge Cycle',
                        style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        '${session.startBatteryLevel}% → ${session.endBatteryLevel}% ($sign$deltaPercent%)',
                        style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${session.durationMinutes} min',
                        style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        '${session.startTime.hour.toString().padLeft(2, '0')}:${session.startTime.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(color: textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatCol('ENERGY', '$sign${session.totalMahDelta.abs()} mAh', accentColor),
                    _buildStatCol('PEAK FLOW', '${session.peakMa.abs()} mA', textColor),
                    _buildStatCol('PEAK POWER', '${session.peakWatts.toStringAsFixed(1)}W', textColor),
                    _buildStatCol(
                      'THERMAL',
                      '${session.minTempCelsius.toStringAsFixed(0)}° - ${session.maxTempCelsius.toStringAsFixed(0)}°C',
                      textColor,
                    ),
                  ],
                ),
              ),
              if (session.topAppName.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Top consumer: ${session.topAppName}',
                  style: TextStyle(color: textMuted, fontSize: 11),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildAppUsageTab(
    Color surfaceColor,
    Color surfaceVariant,
    Color surfaceBorder,
    Color textColor,
    Color textMuted,
    bool isDark,
  ) {
    if (_appUsageList.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: Column(
          children: [
            _buildEmptyState(
              icon: Icons.apps_rounded,
              title: 'App Usage Access Needed',
              subtitle: 'Android requires Usage Access permission to read historical app runtimes and compute battery burn per app.',
              textColor: textColor,
              textMuted: textMuted,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                await _telemetryService.requestIgnoreBatteryOptimizations();
              },
              icon: const Icon(Icons.security_rounded, size: 16),
              label: const Text('Allow Background Running & AutoStart'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentGreen,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _appUsageList.length,
      itemBuilder: (context, index) {
        final app = _appUsageList[index];
        final name = (app['name'] as String?) ?? 'App';
        final minutes = (app['foregroundMinutes'] as num?)?.toInt() ?? 0;
        final usagePercent = (app['usagePercent'] as num?)?.toDouble() ?? 0.0;
        final estimatedMah = (app['estimatedMah'] as num?)?.toInt() ?? 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: surfaceBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.surfaceVariantDark : AppTheme.surfaceVariantLight,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: index < 3 ? AppTheme.accentGreen : textMuted,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$minutes min active  •  ~$estimatedMah mAh',
                      style: TextStyle(color: textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (usagePercent > 20.0 ? AppTheme.amber : AppTheme.accentGreen).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${usagePercent.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: usagePercent > 20.0 ? AppTheme.amber : AppTheme.accentGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStandbyTab(
    Color surfaceColor,
    Color surfaceVariant,
    Color surfaceBorder,
    Color textColor,
    Color textMuted,
    bool isDark,
  ) {
    // Filter samples with sleep intervals > 1 minute for testing & real-world responsiveness
    final sleepSamples = _historicalSamples.where((s) => s.sleepDurationMs > (1000 * 60)).toList();

    if (sleepSamples.isEmpty) {
      return _buildEmptyState(
        icon: Icons.nightlight_round,
        title: 'No sleep standby intervals detected yet',
        subtitle: 'PowerWarden automatically tracks standby sessions when your phone rests overnight or sleeps for >30 minutes.',
        textColor: textColor,
        textMuted: textMuted,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sleepSamples.length,
      itemBuilder: (context, index) {
        final sample = sleepSamples[index];
        final hours = (sample.sleepDurationMs / (1000.0 * 60 * 60)).toStringAsFixed(1);
        final absMa = sample.currentMilliamps.abs();
        final idleBurnRate = ((absMa / 4500.0) * 100.0).toStringAsFixed(1);
        final isCleanSleep = absMa < 280;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCleanSleep ? surfaceBorder : AppTheme.amber.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isCleanSleep ? AppTheme.accentGreen : AppTheme.amber).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.bedtime_rounded,
                  color: isCleanSleep ? AppTheme.accentGreen : AppTheme.amber,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${hours}h Standby Sleep',
                      style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isCleanSleep
                          ? 'Deep sleep healthy • -$idleBurnRate%/hr'
                          : 'Mild wakefulness detected • -$idleBurnRate%/hr',
                      style: TextStyle(
                        color: isCleanSleep ? textMuted : AppTheme.amber,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '-$absMa mA',
                    style: TextStyle(
                      color: isCleanSleep ? AppTheme.chargingCyan : AppTheme.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '${sample.temperatureCelsius.toStringAsFixed(1)}°C',
                    style: TextStyle(color: textMuted, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color textColor,
    required Color textMuted,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: textMuted.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 44, color: textMuted),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(color: textMuted, fontSize: 13, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCol(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
