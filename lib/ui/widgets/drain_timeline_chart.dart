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
    if (samples.isEmpty) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.surfaceBorder),
        ),
        child: const Text(
          'Collecting battery telemetry...',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
      );
    }

    // Generate spots for current mA
    final currentSpots = <FlSpot>[];
    for (int i = 0; i < samples.length; i++) {
      currentSpots.add(FlSpot(i.toDouble(), samples[i].currentMilliamps.toDouble()));
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
    final yInterval = (range > 200 ? (range / 3.0).roundToDouble() : 100.0).clamp(50.0, 500.0);
    final chartMinY = (minVal - 60).clamp(0.0, double.infinity);
    final chartMaxY = maxVal + 60;

    return Container(
      height: 240,
      padding: const EdgeInsets.only(top: 16, bottom: 12, right: 16, left: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'DISCHARGE TIMELINE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: AppTheme.textSecondary,
                  ),
                ),
                  // Legend with Clear Labels
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.chargingCyan, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      const Text('Discharge / Charge Rate (mA)', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: chartMinY,
                maxY: chartMaxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppTheme.surfaceBorder.withOpacity(0.4),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 9, fontWeight: FontWeight.w600),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: currentSpots,
                    isCurved: true,
                    curveSmoothness: 0.2,
                    color: AppTheme.chargingCyan,
                    barWidth: 2.0,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppTheme.chargingCyan.withOpacity(0.18),
                          AppTheme.chargingCyan.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
