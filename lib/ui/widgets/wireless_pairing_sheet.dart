import 'package:flutter/material.dart';
import '../../services/telemetry_service.dart';
import '../theme.dart';

/// Modal bottom sheet for persistent Elevated Authorization via Shizuku.
/// Avoids disappearing Wireless Debugging pairing codes across app switches.
class WirelessPairingSheet extends StatefulWidget {
  final bool hasShizuku;
  final bool hasPermission;
  final VoidCallback onAuthorized;

  const WirelessPairingSheet({
    super.key,
    required this.hasShizuku,
    required this.hasPermission,
    required this.onAuthorized,
  });

  @override
  State<WirelessPairingSheet> createState() => _WirelessPairingSheetState();
}

class _WirelessPairingSheetState extends State<WirelessPairingSheet> {
  final TelemetryService _telemetryService = TelemetryService();
  bool _isRequesting = false;
  String? _statusMessage;

  Future<void> _handleAuthorize() async {
    setState(() {
      _isRequesting = true;
      _statusMessage = null;
    });

    final success = await _telemetryService.requestShizukuPermission();

    if (mounted) {
      setState(() {
        _isRequesting = false;
        _statusMessage = success
            ? '✓ Shizuku permission requested. Tap Allow in the prompt.'
            : '✗ Shizuku service not responding. Please launch the Shizuku app first.';
      });
      if (success) {
        widget.onAuthorized();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                color: AppTheme.surfaceBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_rounded, color: AppTheme.accentGreen, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Persistent Sentinel',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      'Permanent one-tap authorization via Shizuku',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Shizuku binds directly through Android system Binder IPC. Once allowed, PowerWarden permanently retains elevated access to identify runaway loops and unreleased wakelocks without typing pairing codes.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.surfaceBorder),
            ),
            child: Row(
              children: [
                Icon(
                  widget.hasPermission
                      ? Icons.check_circle_rounded
                      : (widget.hasShizuku ? Icons.verified_user_rounded : Icons.info_outline_rounded),
                  color: widget.hasPermission
                      ? AppTheme.accentGreen
                      : (widget.hasShizuku ? AppTheme.chargingCyan : AppTheme.amber),
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Shizuku API Link',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.hasPermission
                            ? 'Authorized & Active'
                            : (widget.hasShizuku ? 'Ready to Authorize' : 'Service not detected'),
                        style: TextStyle(
                          color: widget.hasPermission
                              ? AppTheme.accentGreen
                              : (widget.hasShizuku ? AppTheme.chargingCyan : AppTheme.textMuted),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: widget.hasPermission || _isRequesting ? null : _handleAuthorize,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentGreen,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    widget.hasPermission ? 'Active' : (_isRequesting ? 'Authorizing...' : 'Authorize'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _statusMessage!,
              style: TextStyle(
                fontSize: 12,
                color: _statusMessage!.startsWith('✓') ? AppTheme.accentGreen : AppTheme.crimson,
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
