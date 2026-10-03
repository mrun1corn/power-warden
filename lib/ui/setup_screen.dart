import 'package:flutter/material.dart';
import '../services/telemetry_service.dart';
import 'theme.dart';
import 'widgets/wireless_pairing_sheet.dart';

/// Guided 3-step First Run Onboarding & Setup Screen.
/// Clearly introduces PowerWarden, explains why elevation is needed,
/// allows 1-tap Shizuku / Wireless ADB setup, or lets the user continue with rootless baseline.
class SetupScreen extends StatefulWidget {
  final VoidCallback onSetupComplete;

  const SetupScreen({
    super.key,
    required this.onSetupComplete,
  });

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _telemetryService = TelemetryService();
  int _currentStep = 0;
  bool _isPaired = false;
  Map<String, bool> _elevatedStatus = {};

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final status = await _telemetryService.getElevatedStatus();
    if (mounted) {
      setState(() {
        _elevatedStatus = status;
        _isPaired = status['hasAnyElevatedAccess'] == true;
      });
    }
  }

  void _finishSetup() async {
    await _telemetryService.setPrefBool('has_completed_setup', true);
    widget.onSetupComplete();
  }

  void _openPairing() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WirelessPairingSheet(
        hasShizuku: _elevatedStatus['hasShizuku'] ?? false,
        hasPermission: _elevatedStatus['hasShizukuPermission'] ?? false,
        hasKadb: _elevatedStatus['hasKadb'] ?? false,
        onAuthorized: () async {
          await _checkStatus();
          if (mounted) {
            Navigator.pop(context);
          }
        },
      ),
    ).then((_) async {
      // Re-check status when user returns or closes the pairing sheet
      await _checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pureOledBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top progress bar indicator
              Row(
                children: [
                  _buildStepDot(0),
                  const SizedBox(width: 8),
                  _buildStepDot(1),
                  const SizedBox(width: 8),
                  _buildStepDot(2),
                  const Spacer(),
                  if (_currentStep < 2)
                    TextButton(
                      onPressed: _finishSetup,
                      child: const Text('Skip', style: TextStyle(color: AppTheme.textMuted)),
                    ),
                ],
              ),
              const SizedBox(height: 32),

              Expanded(
                child: switch (_currentStep) {
                  0 => _buildWelcomeStep(),
                  1 => _buildTelemetryIntroStep(),
                  _ => _buildElevationStep(),
   },
 ),

 // Bottom Navigation Controls
 Row(
   children: [
     if (_currentStep > 0)
       OutlinedButton(
         onPressed: () => setState(() => _currentStep--),
         style: OutlinedButton.styleFrom(
           foregroundColor: Colors.white,
           side: const BorderSide(color: AppTheme.surfaceBorder),
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
         ),
         child: const Text('Back'),
       ),
     const Spacer(),
     ElevatedButton(
       onPressed: () {
         if (_currentStep < 2) {
           setState(() => _currentStep++);
         } else {
           _finishSetup();
         }
       },
       style: ElevatedButton.styleFrom(
         backgroundColor: AppTheme.accentGreen,
         foregroundColor: Colors.black,
         elevation: 0,
         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
         padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
       ),
       child: Text(
         _currentStep == 2 ? 'Get Started' : 'Next',
         style: const TextStyle(fontWeight: FontWeight.bold),
       ),
     ),
   ],
 ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepDot(int index) {
    final active = _currentStep == index;
    final done = _currentStep > index;

    return Container(
      width: active ? 32 : 12,
      height: 6,
      decoration: BoxDecoration(
        color: active
            ? AppTheme.accentGreen
            : (done ? AppTheme.accentGreen.withOpacity(0.4) : AppTheme.surfaceVariant),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _buildWelcomeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.accentGreen.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.shield_outlined, size: 48, color: AppTheme.accentGreen),
        ),
        const SizedBox(height: 24),
        const Text(
          'Welcome to\nPowerWarden',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'A quiet, hardware-level battery watchdog that catches rogue background drain loops, silent thermal runaways, and unreleased wakelocks without draining power itself.',
          style: TextStyle(
            fontSize: 15,
            color: AppTheme.textSecondary,
            height: 1.5,
          ),
        ),
        const Spacer(),
        _buildHighlightRow(Icons.check_circle_outline, 'Under 10ms CPU execution footprint'),
        const SizedBox(height: 12),
        _buildHighlightRow(Icons.check_circle_outline, 'OLED pure-black battery saving surface'),
        const SizedBox(height: 12),
        _buildHighlightRow(Icons.check_circle_outline, 'Hardware mA telemetry & thermal filtering'),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildTelemetryIntroStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.chargingCyan.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.bolt_rounded, size: 48, color: AppTheme.chargingCyan),
        ),
        const SizedBox(height: 24),
        const Text(
          'Real Hardware\nMeasurements',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Unlike apps that estimate drain via percentage drops, PowerWarden reads direct physical battery current (mA) from the device fuel-gauge chip, passing it through a 3-point median noise filter.',
          style: TextStyle(
            fontSize: 15,
            color: AppTheme.textSecondary,
            height: 1.5,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.surfaceBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: AppTheme.chargingCyan, size: 24),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'PowerWarden runs a minimal foreground service to monitor standby discharge without waking the CPU.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildElevationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isPaired
                ? AppTheme.accentGreen.withOpacity(0.12)
                : AppTheme.amber.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _isPaired ? Icons.verified_user_rounded : Icons.admin_panel_settings_rounded,
            size: 48,
            color: _isPaired ? AppTheme.accentGreen : AppTheme.amber,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _isPaired ? 'Elevated Access\nGranted & Active' : 'Elevated System\nAccess (Recommended)',
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _isPaired
              ? 'PowerWarden has elevated privileges attached. You have full capability to inspect per-process CPU time and force-stop rogue drain loops.'
              : 'Android restricts unprivileged apps from reading process lists and stopping rogue background tasks. Pair via Shizuku or Wireless ADB for full capability.',
          style: const TextStyle(
            fontSize: 15,
            color: AppTheme.textSecondary,
            height: 1.5,
          ),
        ),
        const Spacer(),
        InkWell(
          onTap: _openPairing,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isPaired
                    ? AppTheme.accentGreen.withOpacity(0.4)
                    : AppTheme.amber.withOpacity(0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isPaired ? Icons.verified_user_rounded : Icons.link_rounded,
                  color: _isPaired ? AppTheme.accentGreen : AppTheme.amber,
                  size: 24,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isPaired ? 'Wireless ADB / Shizuku Configured' : 'Configure Shizuku or Wireless ADB',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isPaired
                            ? 'Pairing active. Tap to re-configure or check status.'
                            : 'Pair once in 30s to grant permanent permissions.',
                        style: TextStyle(
                          color: _isPaired ? AppTheme.accentGreen : AppTheme.amber,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildHighlightRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.accentGreen, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
