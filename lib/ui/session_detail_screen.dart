import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../domain/models/power_session.dart';
import '../domain/models/telemetry_sample.dart';
import 'theme.dart';

/// Full-screen detail view for a single charging/discharging session.
/// Shows the live current/temperature trace, stat grid, and context.
class SessionDetailScreen extends StatefulWidget {
  final PowerSession session;
  final List<TelemetrySample> sessionSamples;

  const SessionDetailScreen({
    super.key,
    required this.session,
    required this.sessionSamples,
  });

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  int? _sessionHoverIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCharging = widget.session.isCharging;
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
          if (widget.sessionSamples.length >= 2) ...[
            _buildChartCard(context, accent, isCharging),
            const SizedBox(height: 16),
          ],
          _buildStatGrid(context, accent, isCharging),
          const SizedBox(height: 16),
          if (widget.session.topAppName.isNotEmpty) _buildTopAppCard(context),
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
                    '${widget.session.startBatteryLevel}% → ${widget.session.endBatteryLevel}%',
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
                    '$sign${(widget.session.endBatteryLevel - widget.session.startBatteryLevel).abs()}%',
                    style: theme.textTheme.labelLarge?.copyWith(color: accent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${PowerFormatters.timestamp(widget.sessionSamples.first.timestamp)} — ${PowerFormatters.timestamp(widget.sessionSamples.last.timestamp)}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Duration: ${widget.session.formattedDuration}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartCard(BuildContext context, Color accent, bool isCharging) {
    final theme = Theme.of(context);
    final samples = widget.sessionSamples.reversed.toList();
    final maxMa = (samples
            .map((e) => e.currentMilliamps.abs().toDouble())
            .reduce((a, b) => a > b ? a : b) *
        1.2)
        .clamp(100, 8000)
        .toDouble();

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
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final box = context.findRenderObject() as RenderBox;
                  final local = box.globalToLocal(details.globalPosition);
                  final width = box.size.width;
                  
                  final plotLeft = 44.0;
                  final plotRight = width - 4.0;
                  final m = samples.length;
                  if (local.dx >= plotLeft && local.dx <= plotRight) {
                    final t = (local.dx - plotLeft) / (plotRight - plotLeft);
                    final idx = (t * (m - 1)).round().clamp(0, m - 1);
                    setState(() => _sessionHoverIndex = idx);
                  }
                },
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _SessionChartPainter(
                    samples: samples,
                    maxY: maxMa,
                    primaryColor: accent,
                    hoverIndex: _sessionHoverIndex,
                  ),
                ),
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
        '${widget.session.totalMahDelta.abs()} mAh',
        Icons.battery_full_rounded
      ),
      (
        isCharging ? 'Peak Speed' : 'Peak Drain',
        '${widget.session.peakMa.abs()} mA',
        Icons.flash_on_rounded
      ),
      (
        isCharging ? 'Peak Power' : 'Peak Power',
        '${widget.session.peakWatts.toStringAsFixed(1)} W',
        Icons.bolt_rounded
      ),
      (
        'Avg Current',
        widget.sessionSamples.length >= 2
            ? '${(widget.sessionSamples.map((s) => s.currentMilliamps.abs()).reduce((a, b) => a + b) / widget.sessionSamples.length).round()} mA'
            : '—',
        Icons.speed_rounded
      ),
      (
        'Temp Range',
        '${widget.session.minTempCelsius.toStringAsFixed(0)}–${widget.session.maxTempCelsius.toStringAsFixed(0)}°C',
        Icons.thermostat_rounded
      ),
      (
        'Avg Voltage',
        widget.sessionSamples.length >= 2
            ? '${(widget.sessionSamples.map((s) => s.voltageMv).reduce((a, b) => a + b) / widget.sessionSamples.length / 1000.0).toStringAsFixed(2)} V'
            : '—',
        Icons.electrical_services_rounded
      ),
      (
        'Screen On',
        widget.session.screenOnSeconds > 0 ? widget.session.formattedDuration : '—',
        Icons.phone_android_rounded
      ),
      (
        'Screen Off',
        widget.session.screenOffSeconds > 0 ? PowerFormatters.duration(Duration(seconds: widget.session.screenOffSeconds)) : '—',
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
        subtitle: Text(widget.session.topAppName, style: theme.textTheme.bodyLarge),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

/// CustomPaint for session detail current trace — no clipping at the edges.
class _SessionChartPainter extends CustomPainter {
  final List<TelemetrySample> samples;
  final double maxY;
  final Color primaryColor;
  final int? hoverIndex;

  _SessionChartPainter({
    required this.samples,
    required this.maxY,
    required this.primaryColor,
    required this.hoverIndex,
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
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;

    final ySteps = 4;
    for (int i = 0; i <= ySteps; i++) {
      final y = plotBottom - (plotH * i / ySteps);
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), gridPaint);
    }

    final pts = <Offset>[];
    for (int i = 0; i < n; i++) {
      final x = plotLeft + ((size.width - 48.0) * i / (n - 1));
      final val = samples[i].currentMilliamps.abs().toDouble() / maxY;
      final y = plotBottom - plotH * val.clamp(0, 1);
      pts.add(Offset(x, y));
    }

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

    final durMin = math.max(
      1,
      (samples.last.timestamp.difference(samples.first.timestamp).inSeconds ~/ 60),
    );
    final leftPaint = TextPainter(
      text: TextSpan(
        text: '-$durMin m',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
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

    for (int i = 0; i <= ySteps; i++) {
      final val = maxY * i / ySteps;
      final y = plotBottom - plotH * (i / ySteps);
      final tickPaint = TextPainter(
        text: TextSpan(
          text: '${val.toInt()}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
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

    if (hoverIndex != null && hoverIndex! >= 0 && hoverIndex! < n) {
      final p = pts[hoverIndex!];
      canvas.drawCircle(p, 4, Paint()..color = primaryColor);
      canvas.drawCircle(p, 2, Paint()..color = Colors.white);

      final val = samples[hoverIndex!].currentMilliamps.abs().toInt();
      final label = '$val mA';
      final labelPaint = TextPainter(
        text: TextSpan(text: label, style: TextStyle(color: Colors.white, fontSize: 9)),
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
  bool shouldRepaint(covariant _SessionChartPainter old) =>
      old.samples != samples || old.maxY != maxY || old.hoverIndex != hoverIndex;
}
