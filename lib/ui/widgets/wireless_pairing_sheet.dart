import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/telemetry_service.dart';
import '../theme.dart';

/// Modal bottom sheet for pairing Shizuku or local Wireless ADB (Kadb).
/// Handles soft keyboard insets smoothly, preventing input overlap.
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
  final _portFocusNode = FocusNode();
  final _codeFocusNode = FocusNode();
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
    _portFocusNode.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handlePairKadb() async {
    FocusScope.of(context).unfocus();
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
            : '✗ Pairing failed. Verify Wireless Debugging is enabled in Dev Options.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedPadding(
        padding: EdgeInsets.only(bottom: bottomInset),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.accentGreen.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.security_rounded, color: AppTheme.accentGreen, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Elevated Diagnostics',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            'Rootless process isolation without a PC',
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
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: AppTheme.accentGreen,
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.black,
                    unselectedLabelColor: AppTheme.textSecondary,
                    indicator: BoxDecoration(
                      color: AppTheme.accentGreen,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: 'Shizuku API'),
                      Tab(text: 'Wireless ADB (Kadb)'),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 270,
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
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppTheme.surfaceBorder),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  widget.hasShizuku ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                  color: widget.hasShizuku ? AppTheme.accentGreen : AppTheme.amber,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Shizuku Manager', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      Text(
                                        widget.hasShizuku ? 'Installed & Ready' : 'Not installed',
                                        style: TextStyle(
                                          color: widget.hasShizuku ? AppTheme.accentGreen : AppTheme.textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: widget.onRequestShizuku,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.accentGreen,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text('Authorize'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Tab 2: Kadb (Wireless ADB)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pair directly on Android 11+ via Developer Options -> Wireless Debugging:',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.3),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _portController,
                                  focusNode: _portFocusNode,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(5),
                                  ],
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                  decoration: InputDecoration(
                                    labelText: 'Port',
                                    labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                    hintText: '37755',
                                    hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                                    filled: true,
                                    fillColor: AppTheme.surfaceVariant,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                  ),
                                  onSubmitted: (_) => _codeFocusNode.requestFocus(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _codeController,
                                  focusNode: _codeFocusNode,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(6),
                                  ],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2.0,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: '6-Digit Code',
                                    labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                    hintText: '123456',
                                    hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13, letterSpacing: 0),
                                    filled: true,
                                    fillColor: AppTheme.surfaceVariant,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                  ),
                                  onSubmitted: (_) => _handlePairKadb(),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton.icon(
                              onPressed: _isPairing ? null : _handlePairKadb,
                              icon: _isPairing
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                  : const Icon(Icons.wifi_tethering_rounded, size: 18),
                              label: Text(
                                _isPairing ? 'Pairing...' : 'Pair Localhost Kadb',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.chargingCyan,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          if (_statusMessage != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _statusMessage!,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: _statusMessage!.startsWith('✓') ? AppTheme.accentGreen : AppTheme.crimson,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
