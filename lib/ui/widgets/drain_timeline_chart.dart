import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../core/formatters.dart';
import '../../domain/models/telemetry_sample.dart';
import '../theme.dart';

/// Interactive drain timeline chart (Syncfusion-powered).
/// Renders instantaneous current magnitude over time with axis labels that
/// never clip at the edges.
class DrainTimelineChart extends StatelessWidget {
  final List<TelemetrySample> samples;

  const DrainTimelineChart({super.key, required this.samples});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (samples.isEmpty) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? AppTheme.surfaceBorderDark
                : AppTheme.surfaceBorderLight,
          ),
        ),
        child: Text(
          'Collecting battery telemetry…',
          style: TextStyle(
            color: isDark
                ? AppTheme.textMuted
                : AppTheme.textMutedLight,
            fontSize: 13,
          ),
        ),
      );
    }

    final isCurrentlyCharging = samples.last.isCharging;
    final primaryColor = isCurrentlyCharging
        ? AppTheme.chargingColor(theme.brightness)
        : AppTheme.healthColor(theme.brightness);

    // Newest sample first, so "Now" sits at the right edge of the chart.
    final chartSamples = samples.reversed.toList();

    final maxMa =
        (chartSamples
            .map((e) => e.currentMilliamps.abs().toDouble())
            .reduce((a, b) => a > b ? a : b) *
            1.15)
        .clamp(200, 9000);

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.dividerTheme.color!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isCurrentlyCharging
                      ? 'CHARGING FLOW TIMELINE'
                      : 'DISCHARGE FLOW TIMELINE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: isDark
                        ? AppTheme.textSecondary
                        : AppTheme.textSecondaryLight,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isCurrentlyCharging
                          ? 'Charge Flow (+mA)'
                          : 'Discharge (-mA)',
                      style: TextStyle(
                        color: isDark
                            ? AppTheme.textSecondary
                            : AppTheme.textSecondaryLight,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
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
                  color: theme.dividerTheme.color?.withValues(alpha: 0.3),
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
                  dataSource: chartSamples,
                  xValueMapper: (TelemetrySample sample, _) =>
                      PowerFormatters.timestamp(sample.timestamp),
                  yValueMapper: (TelemetrySample sample, _) =>
                      sample.currentMilliamps.abs().toDouble(),
                  name: 'Current',
                  color: primaryColor,
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
    );
  }
}
