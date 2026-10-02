import 'package:flutter/material.dart';
import '../../services/telemetry_service.dart';
import '../theme.dart';

/// Modal bottom sheet for pairing Shizuku or local Wireless ADB (Kadb).
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

class _WirelessPairingSheetState extends State<WirelessPairingSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _portController = TextEditingController();
  final _codeController = TextEditingController();
  final TelemetryService _telemetryService = TelemetryService();

  bool _isPairing = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _portController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handlePairKadb() async {
    final port = int.tryParse(_portController.text.trim());
    final code = _codeController.text.trim();

    if (port == null || code.isEmpty) {
      setState(() => _statusMessage = 'Enter both Port & 6-digit Pairing Code');
      return;
    }

    setState(() {
      _isPairing = true;
      _statusMessage = 'Pairing with localhost:$port...';
    });

    final success = await _telemetryService.pairKadb(port, code);

    if (mounted) {
      setState(() {
        _isPairing = false;
        _statusMessage = success
            ? '✓ Successfully paired via Kadb!'
            : '✗ Pairing failed. Verify Wireless Debugging is enabled.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_outlined, color: AppTheme.accentGreen, size: 20),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Elevated Diagnostics',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    'Rootless process isolation without PC',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabController,
            indicatorColor: AppTheme.accentGreen,
            labelColor: AppTheme.accentGreen,
            unselectedLabelColor: AppTheme.textMuted,
            tabs: const [
              Tab(text: 'Shizuku API'),
              Tab(text: 'Wireless ADB (Kadb)'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 240,
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Shizuku
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Shizuku binds to an active ADB daemon to grant elevated system privileges directly.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.surfaceBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            widget.hasShizuku ? Icons.check_circle : Icons.error_outline,
                            color: widget.hasShizuku ? AppTheme.accentGreen : AppTheme.amber,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Shizuku Manager', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              Text(
                                widget.hasShizuku ? 'Installed & Detected' : 'Not installed',
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
                  ],
                ),

                // Tab 2: Kadb (Wireless ADB)
                SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pair directly via Android 11+ Wireless Debugging without installing external apps:',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _portController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'Pairing Port',
                                labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                hintText: 'e.g. 37755',
                                hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                filled: true,
                                fillColor: AppTheme.surfaceVariant,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _codeController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: '6-Digit Code',
                                labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                hintText: 'e.g. 123456',
                                hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                filled: true,
                                fillColor: AppTheme.surfaceVariant,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isPairing ? null : _handlePairKadb,
                          icon: _isPairing
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : const Icon(Icons.wifi_tethering, size: 16),
                          label: Text(_isPairing ? 'Pairing...' : 'Pair Localhost Kadb'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.chargingCyan,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _statusMessage!,
                          style: TextStyle(
                            fontSize: 11,
                            color: _statusMessage!.startsWith('✓') ? AppTheme.accentGreen : AppTheme.crimson,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
