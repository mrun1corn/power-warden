import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database/database.dart';
import '../../main.dart';
import '../../services/telemetry_service.dart';
import 'theme.dart';
import 'widgets/wireless_pairing_sheet.dart';

/// Diagnostics, Elevation, & System Engine Screen.
/// Provides deep management of Shizuku Binder, Wireless ADB, OEM Optimization,
/// and automated local data retention.
class EngineScreen extends StatefulWidget {
  const EngineScreen({super.key});

  @override
  State<EngineScreen> createState() => _EngineScreenState();
}

class _EngineScreenState extends State<EngineScreen> {
  final TelemetryService _telemetryService = TelemetryService();
  final AppDatabase _database = AppDatabase();

  Timer? _autoRefreshTimer;
  Map<String, bool> _elevatedStatus = {};
  bool _isBatteryOptimized = false;
  bool _isAccessibilityActive = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadState();

    // Auto-refresh engine diagnostics every 5 seconds dynamically
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _refreshSilently();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshSilently() async {
    final status = await _telemetryService.getElevatedStatus();
    final isIgnored = await _telemetryService.isBatteryOptimizationIgnored();
    final isAccess = await _telemetryService.isAccessibilityServiceActive();
    if (mounted) {
      setState(() {
        _elevatedStatus = status;
        _isBatteryOptimized = !isIgnored;
        _isAccessibilityActive = isAccess;
      });
    }
  }

  Future<void> _loadState() async {
    setState(() => _isLoading = true);
    final status = await _telemetryService.getElevatedStatus();
    final isIgnored = await _telemetryService.isBatteryOptimizationIgnored();
    final isAccess = await _telemetryService.isAccessibilityServiceActive();

    if (mounted) {
      setState(() {
        _elevatedStatus = status;
        _isBatteryOptimized = !isIgnored;
        _isAccessibilityActive = isAccess;
        _isLoading = false;
      });
    }
  }

  void _openPairingModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WirelessPairingSheet(
        hasShizuku: _elevatedStatus['hasShizuku'] ?? false,
        hasPermission: _elevatedStatus['hasShizukuPermission'] ?? false,
        hasKadb: _elevatedStatus['hasKadb'] ?? false,
        onAuthorized: () async {
          await _loadState();
          if (mounted) Navigator.pop(context);
        },
      ),
    ).then((_) => _loadState());
  }

  void _showVendorAutostartModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.surfaceBorderDark : AppTheme.surfaceBorderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.shield_moon_rounded, color: AppTheme.chargingCyan, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'OEM Autostart & Killer Defense',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Aggressive OEM skins terminate background foreground services unless manually exempted in system security center:',
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              _buildOemTile(
                brand: 'Xiaomi / Redmi / POCO (HyperOS & MIUI)',
                desc: 'Security App → Manage Apps → PowerWarden → Autostart: ON & Battery Saver: No Restrictions',
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _buildOemTile(
                brand: 'Samsung (OneUI)',
                desc: 'Device Care → Battery → Background usage limits → Never sleeping apps → Add PowerWarden',
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _buildOemTile(
                brand: 'OnePlus / OPPO / Realme (ColorOS / OxygenOS)',
                desc: 'App Management → PowerWarden → Battery usage → Allow background activity & Auto-launch',
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _telemetryService.requestIgnoreBatteryOptimizations();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentGreen,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Open System Battery Optimization Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOemTile({required String brand, required String desc, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceVariantDark : AppTheme.surfaceVariantLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(brand, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 2),
          Text(desc, style: TextStyle(fontSize: 11, color: isDark ? AppTheme.textMuted : AppTheme.textMutedLight, height: 1.3)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final surfaceBorder = isDark ? AppTheme.surfaceBorderDark : AppTheme.surfaceBorderLight;
    final textColor = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final textMuted = isDark ? AppTheme.textMuted : AppTheme.textMutedLight;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.pureOledBackground : AppTheme.lightBackground,
      appBar: AppBar(
        title: Text(
          'Engine & Settings',
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadState,
            tooltip: 'Refresh Status',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentGreen))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              children: [
                // Section 0: Appearance & Theme
                _buildSectionHeader('APPEARANCE & DISPLAY THEME', textMuted),
                const SizedBox(height: 8),
                _buildCard(
                  surfaceColor,
                  surfaceBorder,
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (isDark ? AppTheme.accentGreen : AppTheme.chargingCyanLight)
                              .withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                          size: 20,
                          color: isDark ? AppTheme.accentGreen : AppTheme.chargingCyanLight,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isDark ? 'Pure OLED Black Theme' : 'Clean Light Mode',
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isDark
                                  ? 'True #000000 black saves battery on AMOLED displays'
                                  : 'High-contrast light interface (WCAG AA compliant)',
                              style: TextStyle(color: textMuted, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: isDark,
                        activeTrackColor: AppTheme.accentGreen,
                        onChanged: (val) async {
                          final newMode = val ? ThemeMode.dark : ThemeMode.light;
                          PowerWardenApp.themeModeNotifier.value = newMode;
                          await _telemetryService.setPrefBool('is_light_mode', !val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Section 1: Elevated Privilege Status
                _buildSectionHeader('ELEVATED DIAGNOSTICS ENGINE', textMuted),
                const SizedBox(height: 8),
                _buildCard(
                  surfaceColor,
                  surfaceBorder,
                  Column(
                    children: [
                      _buildStatusRow(
                        title: 'Shizuku API (Binder IPC)',
                        subtitle: _elevatedStatus['hasShizukuPermission'] == true
                            ? 'Authorized & Active'
                            : (_elevatedStatus['hasShizuku'] == true
                                ? 'Installed (Needs Permission)'
                                : 'Not Detected'),
                        isActive: _elevatedStatus['hasShizukuPermission'] == true,
                        icon: Icons.verified_user_rounded,
                        textColor: textColor,
                        textMuted: textMuted,
                      ),
                      Divider(color: surfaceBorder, height: 1),
                      _buildStatusRow(
                        title: 'Wireless ADB (Local Kadb)',
                        subtitle: _elevatedStatus['hasKadb'] == true
                            ? 'Connected to 127.0.0.1'
                            : 'Standby / Unpaired',
                        isActive: _elevatedStatus['hasKadb'] == true,
                        icon: Icons.wifi_tethering_rounded,
                        textColor: textColor,
                        textMuted: textMuted,
                      ),
                      Divider(color: surfaceBorder, height: 1),
                      _buildStatusRow(
                        title: 'Permanent Shell Grants',
                        subtitle: _elevatedStatus['hasPermanentAdb'] == true
                            ? 'BATTERY_STATS & USAGE_STATS active'
                            : 'Standard UID Restrictions',
                        isActive: _elevatedStatus['hasPermanentAdb'] == true,
                        icon: Icons.terminal_rounded,
                        textColor: textColor,
                        textMuted: textMuted,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton.icon(
                          onPressed: _openPairingModal,
                          icon: const Icon(Icons.tune_rounded, size: 16),
                          label: const Text('Open Pairing Assistant', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentGreen,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Section 2: Zero-ADB Accessibility Fallback
                _buildSectionHeader('ZERO-ADB REMEDIATION FALLBACK', textMuted),
                const SizedBox(height: 8),
                _buildCard(
                  surfaceColor,
                  surfaceBorder,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusRow(
                        title: 'Warden Accessibility Service',
                        subtitle: _isAccessibilityActive
                            ? 'Automated 1-tap force stop active'
                            : 'Disabled in Accessibility Settings',
                        isActive: _isAccessibilityActive,
                        icon: Icons.accessibility_new_rounded,
                        textColor: textColor,
                        textMuted: textMuted,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Allows PowerWarden to navigate to system App Info and click Force Stop automatically when neither Shizuku nor ADB is paired.',
                        style: TextStyle(fontSize: 12, color: textMuted, height: 1.35),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () async {
                          await _telemetryService.openAccessibilitySettings();
                          await _loadState();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.white : Colors.black,
                          side: BorderSide(color: surfaceBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Open Accessibility Settings'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Section 3: OEM Battery Optimization Exemption
                _buildSectionHeader('OEM SLEEP & KILLER DEFENSE', textMuted),
                const SizedBox(height: 8),
                _buildCard(
                  surfaceColor,
                  surfaceBorder,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusRow(
                        title: 'Battery Saver Exemption',
                        subtitle: !_isBatteryOptimized
                            ? 'Exempted (Continuous background sentinel)'
                            : 'Optimized by OEM (Risk of background kill)',
                        isActive: !_isBatteryOptimized,
                        icon: Icons.battery_saver_rounded,
                        textColor: textColor,
                        textMuted: textMuted,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Exempts PowerWarden from aggressive OEM task-killers (MIUI/HyperOS, Samsung OneUI, ColorOS) to keep screen-off sentinel active.',
                        style: TextStyle(fontSize: 12, color: textMuted, height: 1.35),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                await _telemetryService.requestIgnoreBatteryOptimizations();
                                await _loadState();
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark ? Colors.white : Colors.black,
                                side: BorderSide(color: surfaceBorder),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Exempt Battery Saver'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _showVendorAutostartModal,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.chargingCyan,
                                side: BorderSide(color: AppTheme.chargingCyan.withValues(alpha: 0.4)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('OEM Guides'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Section 4: Data Retention & Storage Maintenance
                _buildSectionHeader('STORAGE & PRUNING WORKER', textMuted),
                const SizedBox(height: 8),
                _buildCard(
                  surfaceColor,
                  surfaceBorder,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rolling 48-Hour Retention Engine',
                        style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Telemetry samples are batched in memory and flushed every 15 minutes. Records older than 48 hours are automatically purged to prevent disk bloat.',
                        style: TextStyle(fontSize: 12, color: textMuted, height: 1.35),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              await _database.pruneOldTelemetry();
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('✓ Pruned telemetry records older than 48 hours'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                            label: const Text('Prune Stale Data'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark ? Colors.white : Colors.black,
                              side: BorderSide(color: surfaceBorder),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: MediaQuery.viewPaddingOf(context).bottom + 24),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title, Color textMuted) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
          color: textMuted,
        ),
      ),
    );
  }

  Widget _buildCard(Color surfaceColor, Color surfaceBorder, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: surfaceBorder),
      ),
      child: child,
    );
  }

  Widget _buildStatusRow({
    required String title,
    required String subtitle,
    required bool isActive,
    required IconData icon,
    required Color textColor,
    required Color textMuted,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isActive
                  ? AppTheme.accentGreen.withValues(alpha: 0.12)
                  : AppTheme.amber.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 18,
              color: isActive ? AppTheme.accentGreen : AppTheme.amber,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isActive
                  ? AppTheme.accentGreen.withValues(alpha: 0.12)
                  : AppTheme.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isActive
                    ? AppTheme.accentGreen.withValues(alpha: 0.3)
                    : AppTheme.amber.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              isActive ? 'ACTIVE' : 'INACTIVE',
              style: TextStyle(
                color: isActive ? AppTheme.accentGreen : AppTheme.amber,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
