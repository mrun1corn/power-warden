import 'package:flutter/material.dart';
import '../theme.dart';

enum ElevatedBackendType {
  none,
  shizuku,
  kadb,
}

class MetricChips extends StatelessWidget {
  final int batteryLevel; // 0 - 100
  final bool isCharging;
  final double temperatureCelsius;
  final int voltageMv;
  final bool isScreenOn;
  final bool hasElevatedAccess;
  final ElevatedBackendType elevatedBackend;
  final VoidCallback? onTapElevated;

  const MetricChips({
    super.key,
    required this.batteryLevel,
    required this.isCharging,
    required this.temperatureCelsius,
    required this.voltageMv,
    required this.isScreenOn,
    this.hasElevatedAccess = false,
    this.elevatedBackend = ElevatedBackendType.none,
    this.onTapElevated,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            alignment: WrapAlignment.start,
            children: [
              _buildBatteryChip(),
              _buildTemperatureChip(),
              _buildVoltageChip(),
              _buildScreenStateChip(),
              _buildElevatedStatusChip(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBatteryChip() {
    Color color;
    if (isCharging) {
      color = AppTheme.chargingCyan;
    } else if (batteryLevel <= 20) {
      color = AppTheme.crimson;
    } else if (batteryLevel <= 40) {
      color = AppTheme.amber;
    } else {
      color = AppTheme.accentGreen;
    }

    return _ChipContainer(
      icon: isCharging ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded,
      iconColor: color,
      label: 'BATTERY',
      value: '$batteryLevel%',
      valueColor: AppTheme.textPrimary,
    );
  }

  Widget _buildTemperatureChip() {
    Color color;
    if (temperatureCelsius >= 42.0) {
      color = AppTheme.crimson;
    } else if (temperatureCelsius >= 38.0) {
      color = AppTheme.amber;
    } else {
      color = AppTheme.textSecondary;
    }

    return _ChipContainer(
      icon: Icons.thermostat_rounded,
      iconColor: color,
      label: 'TEMP',
      value: '${temperatureCelsius.toStringAsFixed(1)}°C',
      valueColor: color == AppTheme.textSecondary ? AppTheme.textPrimary : color,
    );
  }

  Widget _buildVoltageChip() {
    final volts = (voltageMv / 1000.0).toStringAsFixed(2);
    return _ChipContainer(
      icon: Icons.electric_bolt_rounded,
      iconColor: AppTheme.amber,
      label: 'VOLTAGE',
      value: '$voltageMv mV ($volts V)',
      valueColor: AppTheme.textPrimary,
    );
  }

  Widget _buildScreenStateChip() {
    final color = isScreenOn ? AppTheme.chargingCyan : AppTheme.textMuted;
    return _ChipContainer(
      icon: isScreenOn ? Icons.screen_lock_portrait_rounded : Icons.phone_android_rounded,
      iconColor: color,
      label: 'DISPLAY',
      value: isScreenOn ? 'SCREEN ON' : 'SCREEN OFF',
      valueColor: isScreenOn ? AppTheme.chargingCyan : AppTheme.textSecondary,
    );
  }

  Widget _buildElevatedStatusChip() {
    final active = hasElevatedAccess;
    final color = active ? AppTheme.accentGreen : AppTheme.amber;
    String labelText;
    if (active) {
      labelText = elevatedBackend == ElevatedBackendType.shizuku
          ? 'SHIZUKU ACTIVE'
          : 'ADB ACTIVE';
    } else {
      labelText = 'ELEVATED: NONE';
    }

    return InkWell(
      onTap: onTapElevated,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppTheme.accentGreen.withOpacity(0.5) : AppTheme.surfaceBorder,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.security_rounded : Icons.lock_open_rounded,
              size: 15,
              color: color,
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'PRIVILEGE',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  labelText,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (onTapElevated != null) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: AppTheme.textMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChipContainer extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color valueColor;

  const _ChipContainer({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.surfaceBorder, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: iconColor),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
