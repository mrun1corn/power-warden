import 'package:flutter/material.dart';
import '../theme.dart';

/// Modal bottom sheet for pairing Shizuku or local Wireless ADB.
class WirelessPairingSheet extends StatefulWidget {
  final bool hasShizuku;
  final bool hasKadb;
  final VoidCallback onRequestShizuku;

  const WirelessPairingSheet({
    super.key,
    required this.hasShizuku,
    required this.hasKadb,
    required this.onRequestShizuku,
  });

  @override
  State<WirelessPairingSheet> createState() => _WirelessPairingSheetState();
}

class _WirelessPairingSheetState extends State<WirelessPairingSheet> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.security, color: AppTheme.accentGreen),
              const SizedBox(width: 8),
              const Text(
                'Rootless Elevated Inspection',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'To inspect thread-level CPU loops and unreleased wakelocks without root or a PC, pair via Shizuku or Android Wireless Debugging on localhost.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          // Shizuku Option
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.surfaceBorder),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Shizuku Manager', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      widget.hasShizuku ? 'Installed & Ready' : 'Not installed',
                      style: TextStyle(
                        color: widget.hasShizuku ? AppTheme.accentGreen : AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: widget.onRequestShizuku,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentGreen,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Authorize'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
