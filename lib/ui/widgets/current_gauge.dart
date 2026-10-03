import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

class CurrentGauge extends StatefulWidget {
  final int currentMa; // positive = draining, negative = charging (or vice-versa, handled gracefully)
  final bool isCharging;
  final int maxScaleMa;

  const CurrentGauge({
    super.key,
    required this.currentMa,
    required this.isCharging,
    this.maxScaleMa = 2000,
  });

  @override
  State<CurrentGauge> createState() => _CurrentGaugeState();
}

class _CurrentGaugeState extends State<CurrentGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _needleAnimation;
  double _targetNormalized = 0.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _targetNormalized = _computeNormalizedValue(widget.currentMa);
    _needleAnimation = Tween<double>(begin: _targetNormalized, end: _targetNormalized)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
  }

  @override
  void didUpdateWidget(covariant CurrentGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentMa != widget.currentMa ||
        oldWidget.isCharging != widget.isCharging ||
        oldWidget.maxScaleMa != widget.maxScaleMa) {
      final newNormalized = _computeNormalizedValue(widget.currentMa);
      _needleAnimation = Tween<double>(
        begin: _needleAnimation.value,
        end: newNormalized,
      ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
      _animController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  double _computeNormalizedValue(int ma) {
    final absMa = ma.abs();
    final clamped = absMa.clamp(0, widget.maxScaleMa).toDouble();
    return clamped / widget.maxScaleMa;
  }

  Color _getStatusColor() {
    if (widget.isCharging) {
      return AppTheme.chargingCyan;
    }
    final absMa = widget.currentMa.abs();
    // Context-aware: 400-650mA is normal active drain while interacting with modern screens
    if (absMa > 850) {
      return AppTheme.crimson;
    } else if (absMa > 650) {
      return AppTheme.amber;
    } else {
      return AppTheme.chargingCyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();
    final displayMa = widget.currentMa.abs();

    return Center(
      child: Container(
        width: 250,
        height: 200,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: statusColor.withOpacity(0.08),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: _needleAnimation,
          builder: (context, _) {
            return CustomPaint(
              painter: _HudGaugePainter(
                value: _needleAnimation.value,
                statusColor: statusColor,
                isCharging: widget.isCharging,
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 15.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: statusColor.withOpacity(0.4), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              widget.isCharging ? 'CHARGING' : 'DISCHARGING',
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$displayMa',
                            style: const TextStyle(
                              fontSize: 54,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.5,
                              color: Colors.white,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'mA',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.isCharging ? 'INFLOW CURRENT' : 'INSTANT VELOCITY',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HudGaugePainter extends CustomPainter {
  final double value;
  final Color statusColor;
  final bool isCharging;

  _HudGaugePainter({
    required this.value,
    required this.statusColor,
    required this.isCharging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 10);
    final radius = size.width / 2 - 20;

    const startAngle = 135 * (math.pi / 180);
    const sweepTotal = 270 * (math.pi / 180);

    final bgPaint = Paint()
      ..color = AppTheme.surfaceVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal,
      false,
      bgPaint,
    );

    final activePaint = Paint()
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepTotal,
        colors: [
          isCharging ? AppTheme.chargingCyan : AppTheme.chargingCyan,
          isCharging ? AppTheme.chargingCyan : statusColor,
          statusColor,
        ],
        stops: const [0.0, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    final currentSweep = sweepTotal * value.clamp(0.01, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      currentSweep,
      false,
      activePaint,
    );

    final tickPaint = Paint()
      ..color = AppTheme.surfaceBorder
      ..strokeWidth = 1.5;

    for (int i = 0; i <= 20; i++) {
      final angle = startAngle + (sweepTotal * (i / 20));
      final inner = radius - 16;
      final outer = radius - 8;

      final p1 = Offset(center.dx + inner * math.cos(angle), center.dy + inner * math.sin(angle));
      final p2 = Offset(center.dx + outer * math.cos(angle), center.dy + outer * math.sin(angle));
      canvas.drawLine(p1, p2, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HudGaugePainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.statusColor != statusColor;
  }
}
