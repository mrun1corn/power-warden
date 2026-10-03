import 'package:flutter/material.dart';

import '../../data/database/database.dart';
import '../../domain/models/power_session.dart';
import 'theme.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final AppDatabase _database = AppDatabase();
  List<PowerSession> _sessions = [];
  bool _isLoading = true;
  String _selectedFilter = 'ALL'; // 'ALL', 'CHARGING', 'DISCHARGING'

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final data = await _database.getRecentSessions(limit: 50);
    if (mounted) {
      setState(() {
        _sessions = data;
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

    final filteredSessions = _sessions.where((s) {
      if (_selectedFilter == 'CHARGING') return s.isCharging;
      if (_selectedFilter == 'DISCHARGING') return !s.isCharging;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Power History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadHistory,
            tooltip: 'Refresh History',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs (ALL / CHARGING / DISCHARGING)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterChip('ALL', 'All Sessions', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('CHARGING', '⚡ Charging', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('DISCHARGING', '🔋 Discharging', isDark),
              ],
            ),
          ),

          // Session List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredSessions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_rounded, size: 48, color: textMuted),
                            const SizedBox(height: 12),
                            Text(
                              'No historical sessions recorded yet',
                              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Plug in or use your phone to generate power history',
                              style: TextStyle(color: textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: filteredSessions.length,
                        itemBuilder: (context, index) {
                          final session = filteredSessions[index];
                          return _buildSessionCard(
                            session,
                            surfaceColor: surfaceColor,
                            surfaceVariant: surfaceVariant,
                            surfaceBorder: surfaceBorder,
                            textColor: textColor,
                            textMuted: textMuted,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, bool isDark) {
    final isSelected = _selectedFilter == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilter = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (key == 'CHARGING'
                    ? AppTheme.chargingCyan.withValues(alpha: 0.15)
                    : (key == 'DISCHARGING'
                        ? AppTheme.accentGreen.withValues(alpha: 0.15)
                        : (isDark ? AppTheme.surfaceVariantDark : AppTheme.surfaceVariantLight)))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? (key == 'CHARGING'
                      ? AppTheme.chargingCyan
                      : (key == 'DISCHARGING' ? AppTheme.accentGreen : AppTheme.textSecondary))
                  : (isDark ? AppTheme.surfaceBorderDark : AppTheme.surfaceBorderLight),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected
                  ? (key == 'CHARGING'
                      ? AppTheme.chargingCyan
                      : (key == 'DISCHARGING' ? AppTheme.accentGreen : Colors.white))
                  : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionCard(
    PowerSession session, {
    required Color surfaceColor,
    required Color surfaceVariant,
    required Color surfaceBorder,
    required Color textColor,
    required Color textMuted,
  }) {
    final isCharging = session.isCharging;
    final accentColor = isCharging ? AppTheme.chargingCyan : AppTheme.accentGreen;
    final sign = isCharging ? '+' : '-';
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
          // Header Row: Session Type Icon, Delta %, Duration, Time
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCharging ? Icons.flash_on_rounded : Icons.battery_charging_full_rounded,
                  color: accentColor,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCharging ? 'Charge Session' : 'Discharge Session',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '${session.startBatteryLevel}% → ${session.endBatteryLevel}% ($sign$deltaPercent%)',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${session.durationMinutes} min',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
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

          // Detail Ribbon: mAh gained/lost, Peak Current, Peak Watts / Burn Rate, Temp Range
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: surfaceVariant,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatItem('ENERGY', '$sign${session.totalMahDelta.abs()} mAh', accentColor),
                _buildStatItem('PEAK FLOW', '${session.peakMa.abs()} mA', textColor),
                _buildStatItem('PEAK POWER', '${session.peakWatts.toStringAsFixed(1)}W', textColor),
                _buildStatItem(
                  'TEMP',
                  '${session.minTempCelsius.toStringAsFixed(0)}° - ${session.maxTempCelsius.toStringAsFixed(0)}°C',
                  textColor,
                ),
              ],
            ),
          ),

          // Top App Attribution if available
          if (session.topAppName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.pie_chart_outline_rounded, size: 12, color: textMuted),
                const SizedBox(width: 4),
                Text(
                  'Primary consumer: ${session.topAppName}',
                  style: TextStyle(color: textMuted, fontSize: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
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
