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
    if (absMa > 800) {
      return AppTheme.crimson;
    } else if (absMa > 400) {
      return AppTheme.amber;
    } else {
      return AppTheme.accentGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();
    final isDraining = !widget.isCharging;
    final displayMa = widget.currentMa.abs();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, 280.0);

        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: AnimatedBuilder(
              animation: _needleAnimation,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size(size, size),
                      painter: _GaugePainter(
                        normalizedValue: _needleAnimation.value,
                        isCharging: widget.isCharging,
                        themeColor: statusColor,
                      ),
                    ),
                    Positioned(
                      bottom: size * 0.16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Status Badge (DRAINING / CHARGING)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: statusColor.withOpacity(0.4),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  widget.isCharging
                                      ? Icons.bolt
                                      : (displayMa > 800
                                          ? Icons.warning_amber_rounded
                                          : Icons.arrow_downward_rounded),
                                  size: 14,
                                  color: statusColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  widget.isCharging ? 'CHARGING' : 'DRAINING',
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Current mA Reading
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '${isDraining ? "-" : "+"}$displayMa',
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'mA',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            widget.isCharging
                                ? 'Charge Current'
                                : (displayMa > 800
                                    ? 'High Idle Spike'
                                    : 'Instantaneous Draw'),
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double normalizedValue; // 0.0 to 1.0
  final bool isCharging;
  final Color themeColor;

  _GaugePainter({
    required this.normalizedValue,
    required this.isCharging,
    required this.themeColor,
  });

  // 240 degree sweep arc
  // Starts at 150 deg (5*pi/6) and sweeps 240 deg (4*pi/3) to 390 deg (30 deg)
  static const double _startAngle = 150 * (math.pi / 180);
  static const double _sweepAngle = 240 * (math.pi / 180);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 16;

    final trackPaint = Paint()
      ..color = const Color(0xFF1E1E1E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = themeColor.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    if (isCharging) {
      activePaint.color = AppTheme.chargingCyan;
    } else {
      activePaint.shader = SweepGradient(
        startAngle: _startAngle,
        endAngle: _startAngle + _sweepAngle,
        colors: const [
          AppTheme.accentGreen,
          AppTheme.amber,
          AppTheme.crimson,
        ],
        stops: const [0.0, 0.45, 1.0],
        transform: GradientRotation(_startAngle),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    }

    final arcRect = Rect.fromCircle(center: center, radius: radius);

    // Draw background track
    canvas.drawArc(arcRect, _startAngle, _sweepAngle, false, trackPaint);

    // Active arc progress
    final currentSweep = _sweepAngle * normalizedValue.clamp(0.01, 1.0);
    if (normalizedValue > 0.02) {
      canvas.drawArc(arcRect, _startAngle, currentSweep, false, glowPaint);
    }
    canvas.drawArc(arcRect, _startAngle, currentSweep, false, activePaint);

    // Tick marks
    _drawTicks(canvas, center, radius);

    // Needle indicator
    _drawNeedle(canvas, center, radius);
  }

  void _drawTicks(Canvas canvas, Offset center, double radius) {
    const totalTicks = 9;
    final tickPaint = Paint()
      ..color = const Color(0xFF424242)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < totalTicks; i++) {
      final ratio = i / (totalTicks - 1);
      final angle = _startAngle + (_sweepAngle * ratio);
      final outerX = center.dx + (radius + 12) * math.cos(angle);
      final outerY = center.dy + (radius + 12) * math.sin(angle);
      final innerX = center.dx + (radius + 6) * math.cos(angle);
      final innerY = center.dy + (radius + 6) * math.sin(angle);

      canvas.drawLine(Offset(innerX, innerY), Offset(outerX, outerY), tickPaint);
    }
  }

  void _drawNeedle(Canvas canvas, Offset center, double radius) {
    final currentAngle = _startAngle + (_sweepAngle * normalizedValue.clamp(0.0, 1.0));
    final needleLength = radius - 8;

    final needleTip = Offset(
      center.dx + needleLength * math.cos(currentAngle),
      center.dy + needleLength * math.sin(currentAngle),
    );

    // Center pivot circle
    final pivotPaint = Paint()
      ..color = const Color(0xFF1E1E1E)
      ..style = PaintingStyle.fill;
    final pivotBorderPaint = Paint()
      ..color = themeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    // Needle line
    final needlePaint = Paint()
      ..color = themeColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(center, needleTip, needlePaint);
    canvas.drawCircle(center, 7, pivotPaint);
    canvas.drawCircle(center, 7, pivotBorderPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.normalizedValue != normalizedValue ||
        oldDelegate.isCharging != isCharging ||
        oldDelegate.themeColor != themeColor;
  }
}
