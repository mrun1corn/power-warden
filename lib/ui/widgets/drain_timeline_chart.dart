import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../domain/models/telemetry_sample.dart';
import '../theme.dart';

/// Interactive Multi-Series Drain Timeline Chart.
/// Plots instantaneous discharge mA, battery percentage, and highlights screen-off intervals.
class DrainTimelineChart extends StatelessWidget {
  final List<TelemetrySample> samples;

  const DrainTimelineChart({super.key, required this.samples});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final surfaceBorder = isDark
        ? AppTheme.surfaceBorderDark
        : AppTheme.surfaceBorderLight;
    final textMuted = isDark ? AppTheme.textMuted : AppTheme.textMutedLight;

    if (samples.isEmpty) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: surfaceBorder),
        ),
        child: Text(
          'Collecting battery telemetry...',
          style: TextStyle(color: textMuted, fontSize: 13),
        ),
      );
    }

    // Generate spots for current magnitude in mA (always positive to prevent negative plunging spikes)
    final currentSpots = <FlSpot>[];
    for (int i = 0; i < samples.length; i++) {
      currentSpots.add(
        FlSpot(i.toDouble(), samples[i].currentMilliamps.abs().toDouble()),
      );
    }

    // Find bounds with safety margin to prevent labels from colliding or clipping
    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;
    for (final s in currentSpots) {
      if (s.y < minVal) minVal = s.y;
      if (s.y > maxVal) maxVal = s.y;
    }
    if (minVal.isInfinite) minVal = 0.0;
    if (maxVal.isInfinite) maxVal = 1000.0;

    final range = (maxVal - minVal).abs();
    final yInterval = (range > 200 ? (range / 3.0).roundToDouble() : 100.0)
        .clamp(50.0, 500.0);
    final chartMinY = (minVal - 60).clamp(0.0, double.infinity);
    final chartMaxY = maxVal + 60;

    final isCurrentlyCharging = samples.isNotEmpty && samples.last.isCharging;
    final primaryColor = isCurrentlyCharging ? AppTheme.chargingCyan : AppTheme.accentGreen;
    final eventTitle = isCurrentlyCharging ? 'CHARGING FLOW TIMELINE' : 'DISCHARGE FLOW TIMELINE';
    final flowLabel = isCurrentlyCharging ? 'Charge Flow (+mA)' : 'Discharge (-mA)';

    return Container(
      height: 240,
      padding: const EdgeInsets.only(top: 16, bottom: 12, right: 16, left: 4),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: surfaceBorder),
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
                  eventTitle,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: textMuted,
                  ),
                ),
                // Legend with Clear Event Labels
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
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
                      flowLabel,
                      style: TextStyle(color: textMuted, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LineChart(
                LineChartData(
                  clipData: const FlClipData.all(), // Prevents line and gradient fill from bleeding outside the chart bounding box!
                  minY: chartMinY,
                  maxY: chartMaxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: surfaceBorder,
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: (samples.length > 20
                            ? (samples.length / 3.0)
                            : 10.0),
                        getTitlesWidget: (val, meta) {
                          final idx = val.toInt();
                          if (idx == 0) {
                            return Text(
                              '-${(samples.length * 2) ~/ 60}m',
                              style: TextStyle(color: textMuted, fontSize: 9),
                            );
                          } else if (idx >= samples.length - 1) {
                            return Text(
                              'Now',
                              style: TextStyle(
                                color: textMuted,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        interval: yInterval,
                        getTitlesWidget: (val, meta) {
                          if (val == meta.max || val == meta.min) {
                            return const SizedBox.shrink(); // Prevent edge clipping at top & bottom borders!
                          }
                          return Text(
                            '${val.toInt()} mA',
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    handleBuiltInTouches: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) =>
                          isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
                      tooltipBorder: BorderSide(color: surfaceBorder),
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final idx = spot.x.toInt().clamp(0, samples.length - 1);
                          final s = samples[idx];
                          final eventSign = s.isCharging ? '+' : '-';
                          final eventType = s.isCharging ? 'Charging' : 'Discharging';
                          final screenLabel = s.isScreenOn ? 'Screen On' : 'Asleep';
                          return LineTooltipItem(
                            '$eventSign${spot.y.toInt()} mA ($eventType · ${s.batteryLevel}%)\n${s.temperatureCelsius.toStringAsFixed(1)}°C • $screenLabel',
                            TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: currentSpots,
                      isCurved: true,
                      curveSmoothness: 0.2,
                      color: primaryColor,
                      barWidth: 2.2,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            primaryColor.withValues(alpha: 0.2),
                            primaryColor.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
