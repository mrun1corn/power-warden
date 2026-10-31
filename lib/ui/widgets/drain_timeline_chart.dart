import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/models/telemetry_sample.dart';
import '../theme.dart';
/// Pure-Material drain timeline chart (CustomPaint — no third-party chart
/// library, so axis labels never clip at the edges).
class DrainTimelineChart extends StatefulWidget {
  final List<TelemetrySample> samples;
  const DrainTimelineChart({super.key, required this.samples});
  @override
  State<DrainTimelineChart> createState() => _DrainTimelineChartState();
}
class _DrainTimelineChartState extends State<DrainTimelineChart> {
  int? _hoverIndex;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    if (widget.samples.isEmpty) {
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
            color: isDark ? AppTheme.textMuted : AppTheme.textMutedLight,
            fontSize: 13,
          ),
        ),
      );
    }
    final isCharging = widget.samples.last.isCharging;
    final primaryColor = isCharging
        ? AppTheme.chargingColor(theme.brightness)
        : AppTheme.healthColor(theme.brightness);
    // Newest sample first so "Now" sits at the right edge.
    final chartSamples = widget.samples.reversed.toList();
    final n = chartSamples.length;
    final maxY =
        chartSamples
            .map((e) => e.currentMilliamps.abs().toDouble())
            .reduce((a, b) => a > b ? a : b) *
            1.15;
    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerTheme.color!),
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
                  isCharging ? 'CHARGING FLOW TIMELINE' : 'DISCHARGE FLOW TIMELINE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
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
                      isCharging ? 'Charge Flow (+mA)' : 'Discharge (-mA)',
                      style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
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
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final box = context.findRenderObject() as RenderBox;
                final local = box.globalToLocal(details.globalPosition);
                final width = box.size.width;
                
                final plotLeft = 44.0;
                final plotRight = width - 4.0;
                if (local.dx >= plotLeft && local.dx <= plotRight) {
                  final t = (local.dx - plotLeft) / (plotRight - plotLeft);
                  final idx = (t * (n - 1)).round().clamp(0, n - 1);
                  setState(() => _hoverIndex = idx);
                }
              },
              child: CustomPaint(
                size: Size.infinite,
                painter: _DrainChartPainter(
                  samples: chartSamples,
                  maxY: maxY,
                  primaryColor: primaryColor,
                  hoverIndex: _hoverIndex,
                  isDark: isDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
class _DrainChartPainter extends CustomPainter {
  final List<TelemetrySample> samples;
  final double maxY;
  final Color primaryColor;
  final int? hoverIndex;
  final bool isDark;
  _DrainChartPainter({
    required this.samples,
    required this.maxY,
    required this.primaryColor,
    required this.hoverIndex,
    required this.isDark,
  }) : super(repaint: null);
  @override
  void paint(Canvas canvas, Size size) {
    final n = samples.length;
    if (n < 2) return;
    final plotLeft = 44.0;
    final plotRight = size.width - 4.0;
    final plotTop = 4.0;
    final plotBottom = size.height - 20.0;
    final plotH = plotBottom - plotTop;
    final gridPaint = Paint()
      ..color = (isDark ? AppTheme.surfaceBorderDark : AppTheme.surfaceBorderLight)
          .withValues(alpha: 0.25)
      ..strokeWidth = 0.5;
    // Horizontal gridlines.
    final ySteps = 4;
    for (int i = 0; i <= ySteps; i++) {
      final y = plotBottom - (plotH * i / ySteps);
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), gridPaint);
    }
    // Map sample index -> x, value -> y.
    final pts = <Offset>[];
    for (int i = 0; i < n; i++) {
      final x = plotLeft + ((size.width - 48.0) * i / (n - 1));
      final val = samples[i].currentMilliamps.abs().toDouble() / maxY;
      final y = plotBottom - plotH * val.clamp(0, 1);
      pts.add(Offset(x, y));
    }
    // Area fill under curve.
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryColor.withValues(alpha: 0.16),
          primaryColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTRB(plotLeft, plotTop, plotRight, plotBottom));
    final fillPath = Path();
    fillPath.moveTo(plotLeft, plotBottom);
    for (final p in pts) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(plotRight, plotBottom);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);
    // Curve line.
    final linePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    path.moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < n; i++) {
      final cp = Offset((pts[i - 1].dx + pts[i].dx) / 2, (pts[i - 1].dy + pts[i].dy) / 2);
      path.cubicTo(cp.dx, cp.dy, cp.dx, cp.dy, pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(path, linePaint);
    // Axis labels: "-N m" at left, "Now" at right.
    final durMin = math.max(
      1,
      (samples.last.timestamp.difference(samples.first.timestamp).inSeconds ~/ 60),
    );
    final leftPaint = TextPainter(
      text: TextSpan(
        text: '-$durMin m',
        style: TextStyle(
          color: isDark ? AppTheme.textMuted : AppTheme.textMutedLight,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    leftPaint.layout();
    leftPaint.paint(
      canvas,
      Offset(plotLeft - leftPaint.width - 8, plotBottom + 4),
    );
    final nowPaint = TextPainter(
      text: TextSpan(
        text: 'Now',
        style: TextStyle(
          color: primaryColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    nowPaint.layout();
    nowPaint.paint(
      canvas,
      Offset(plotRight - nowPaint.width / 2, plotBottom + 4),
    );
    // Current tick labels on right edge.
    for (int i = 0; i <= ySteps; i++) {
      final val = maxY * i / ySteps;
      final y = plotBottom - plotH * (i / ySteps);
      final tickPaint = TextPainter(
        text: TextSpan(
          text: '${val.toInt()}',
          style: TextStyle(
            color: isDark ? AppTheme.textMuted : AppTheme.textMutedLight,
            fontSize: 8,
          ),
        ),
        textAlign: TextAlign.right,
        textDirection: TextDirection.ltr,
      );
      tickPaint.layout();
      tickPaint.paint(
        canvas,
        Offset(plotLeft - tickPaint.width - 6, y - tickPaint.height / 2),
      );
    }
    // Hover dot + tooltip.
    if (hoverIndex != null && hoverIndex! >= 0 && hoverIndex! < n) {
      final p = pts[hoverIndex!];
      canvas.drawCircle(p, 4, Paint()..color = primaryColor);
      canvas.drawCircle(p, 2, Paint()..color = Colors.white);
      final val = samples[hoverIndex!].currentMilliamps.abs().toInt();
      final label = '$val mA';
      final labelPaint = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: Colors.white, fontSize: 9),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      labelPaint.layout();
      final labelX = (p.dx - labelPaint.width / 2).clamp(4.0, size.width - labelPaint.width - 4.0);
      final labelY = (p.dy - labelPaint.height - 8).clamp(4.0, plotTop - labelPaint.height - 4.0);
      canvas.drawRRect(
        RRect.fromLTRBR(
          labelX - 4,
          labelY - 4,
          labelX + labelPaint.width + 4,
          labelY + labelPaint.height + 4,
          const Radius.circular(4),
        ),
        Paint()..color = primaryColor.withValues(alpha: 0.9),
      );
      labelPaint.paint(canvas, Offset(labelX, labelY));
    }
  }
  @override
  bool shouldRepaint(covariant _DrainChartPainter old) =>
      old.samples != samples || old.maxY != maxY || old.hoverIndex != hoverIndex;
}
