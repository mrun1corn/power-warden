import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../domain/models/power_session.dart';
import '../domain/models/telemetry_sample.dart';
import 'theme.dart';

/// Full-screen detail view for a single charging/discharging session.
/// Shows the live current/temperature trace, stat grid, and context.
class SessionDetailScreen extends StatelessWidget {
  final PowerSession session;
  final List<TelemetrySample> sessionSamples;

  const SessionDetailScreen({
    super.key,
    required this.session,
    required this.sessionSamples,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCharging = session.isCharging;
    final accent = isCharging
        ? AppTheme.chargingColor(theme.brightness)
        : AppTheme.healthColor(theme.brightness);

    return Scaffold(
      appBar: AppBar(
        title: Text(isCharging ? 'Charge Session' : 'Discharge Session'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeaderCard(context, accent, isCharging),
          const SizedBox(height: 16),
          if (sessionSamples.length >= 2) ...[
            _buildChartCard(context, accent, isCharging),
            const SizedBox(height: 16),
          ],
          _buildStatGrid(context, accent, isCharging),
          const SizedBox(height: 16),
          if (session.topAppName.isNotEmpty) _buildTopAppCard(context),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context, Color accent, bool isCharging) {
    final theme = Theme.of(context);
    final sign = isCharging ? '+' : '-';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isCharging ? Icons.bolt_rounded : Icons.battery_alert_rounded,
                  color: accent,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${session.startBatteryLevel}% → ${session.endBatteryLevel}%',
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$sign${(session.endBatteryLevel - session.startBatteryLevel).abs()}%',
                    style: theme.textTheme.labelLarge?.copyWith(color: accent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${PowerFormatters.timestamp(session.startTime)} — ${PowerFormatters.timestamp(session.endTime)}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Duration: ${session.formattedDuration}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartCard(BuildContext context, Color accent, bool isCharging) {
    final theme = Theme.of(context);
    final samples = sessionSamples.reversed.toList();
    final maxMa =
        (samples.map((e) => e.currentMilliamps.abs().toDouble())
                .reduce((a, b) => a > b ? a : b) *
            1.2)
        .clamp(100, 8000);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCharging ? 'CHARGER INPUT TRACE' : 'DRAIN CURRENT TRACE',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: SfCartesianChart(
                plotAreaBorderWidth: 0,
                primaryXAxis: CategoryAxis(
                  labelStyle: TextStyle(
                    color: theme.textTheme.bodySmall?.color,
                    fontSize: 9,
                  ),
                  majorTickLines: const MajorTickLines(size: 0),
                  axisLine: const AxisLine(width: 0),
                  labelAlignment: LabelAlignment.center,
                  majorGridLines: const MajorGridLines(width: 0),
                ),
                primaryYAxis: NumericAxis(
                  minimum: 0,
                  maximum: maxMa.toDouble(),
                  labelStyle: TextStyle(
                    color: theme.textTheme.bodySmall?.color,
                    fontSize: 9,
                  ),
                  majorTickLines: const MajorTickLines(size: 4),
                  axisLine: const AxisLine(width: 0.5),
                  labelFormat: '{value}mA',
                  majorGridLines: MajorGridLines(
                    color: theme.dividerTheme.color?.withValues(alpha: 0.4),
                    width: 0.5,
                  ),
                ),
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  header: '',
                  format: 'point.x\npoint.y mA',
                  canShowMarker: false,
                ),
                series: <CartesianSeries<TelemetrySample, String>>[
                  LineSeries<TelemetrySample, String>(
                    dataSource: samples,
                    xValueMapper: (TelemetrySample sample, _) =>
                        PowerFormatters.timestamp(sample.timestamp),
                    yValueMapper: (TelemetrySample sample, _) =>
                        sample.currentMilliamps.abs().toDouble(),
                    name: isCharging ? 'Charge Input' : 'Drain Current',
                    color: accent,
                    width: 2,
                    markerSettings: const MarkerSettings(isVisible: false),
                    enableTooltip: true,
                    animationDuration: 600,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatGrid(BuildContext context, Color accent, bool isCharging) {
    final theme = Theme.of(context);
    final stats = <(String, String, IconData)>[
      (
        isCharging ? 'Energy Gained' : 'Energy Lost',
        '${session.totalMahDelta.abs()} mAh',
        Icons.battery_full_rounded
      ),
      (
        isCharging ? 'Peak Speed' : 'Peak Drain',
        '${session.peakMa.abs()} mA',
        Icons.flash_on_rounded
      ),
      (
        isCharging ? 'Peak Power' : 'Peak Power',
        '${session.peakWatts.toStringAsFixed(1)} W',
        Icons.bolt_rounded
      ),
      (
        'Avg Current',
        sessionSamples.length >= 2
            ? '${(sessionSamples.map((s) => s.currentMilliamps.abs()).reduce((a, b) => a + b) / sessionSamples.length).round()} mA'
            : '—',
        Icons.speed_rounded
      ),
      (
        'Temp Range',
        '${session.minTempCelsius.toStringAsFixed(0)}–${session.maxTempCelsius.toStringAsFixed(0)}°C',
        Icons.thermostat_rounded
      ),
      (
        'Avg Voltage',
        sessionSamples.length >= 2
            ? '${(sessionSamples.map((s) => s.voltageMv).reduce((a, b) => a + b) / sessionSamples.length / 1000.0).toStringAsFixed(2)} V'
            : '—',
        Icons.electrical_services_rounded
      ),
      (
        'Screen On',
        session.screenOnSeconds > 0 ? session.formattedDuration : '—',
        Icons.phone_android_rounded
      ),
      (
        'Screen Off',
        session.screenOffSeconds > 0 ? PowerFormatters.duration(Duration(seconds: session.screenOffSeconds)) : '—',
        Icons.nightlight_round
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.9,
      ),
      itemCount: stats.length,
      itemBuilder: (context, i) {
        final (label, value, icon) = stats[i];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 14, color: accent.withValues(alpha: 0.8)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label.toUpperCase(),
                        style: theme.textTheme.labelSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopAppCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.apps_rounded),
        title: Text('Top Consumer', style: theme.textTheme.titleSmall),
        subtitle: Text(session.topAppName, style: theme.textTheme.bodyLarge),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
