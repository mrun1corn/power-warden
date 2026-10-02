import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/telemetry_service.dart';
import '../theme.dart';

/// Dual-Engine modal bottom sheet:
/// 1. Shizuku (Recommended, persistent Binder IPC)
/// 2. Kadb / Wireless Debugging (Direct localhost pairing without external apps)
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

class _WirelessPairingSheetState extends State<WirelessPairingSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TelemetryService _telemetryService = TelemetryService();

  final _portController = TextEditingController();
  final _codeController = TextEditingController();
  final _portFocus = FocusNode();
  final _codeFocus = FocusNode();

  bool _isRequesting = false;
  bool _isPairingKadb = false;
  String? _shizukuMessage;
  String? _kadbMessage;

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
    _portFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _handleShizukuAuthorize() async {
    setState(() {
      _isRequesting = true;
      _shizukuMessage = null;
    });

    final success = await _telemetryService.requestShizukuPermission();

    if (mounted) {
      setState(() {
        _isRequesting = false;
        _shizukuMessage = success
            ? '✓ Permission requested! Please check the Shizuku prompt.'
            : '✗ Shizuku service not responding. Please make sure Shizuku app is running.';
      });
      if (success) {
        widget.onAuthorized();
      }
    }
  }

  Future<void> _handleKadbPair() async {
    FocusScope.of(context).unfocus();
    final port = int.tryParse(_portController.text.trim());
    final code = _codeController.text.trim();

    if (port == null || code.isEmpty) {
      setState(() => _kadbMessage = 'Enter both Port & 6-digit Code.');
      return;
    }

    setState(() {
      _isPairingKadb = true;
      _kadbMessage = 'Pairing with localhost:$port...';
    });

    final ok = await _telemetryService.pairKadb(port, code);

    if (mounted) {
      setState(() {
        _isPairingKadb = false;
        _kadbMessage = ok
            ? '✓ Successfully paired via Wireless ADB!'
            : '✗ Pairing failed. Verify Wireless Debugging is on.';
      });
      if (ok) {
        widget.onAuthorized();
      }
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
                      child: const Icon(Icons.shield_rounded, color: AppTheme.accentGreen, size: 20),
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
                            'Isolate rogue background loops without PC',
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
                const SizedBox(height: 14),
                // Tabs
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.black,
                    unselectedLabelColor: AppTheme.textSecondary,
                    indicator: BoxDecoration(
                      color: AppTheme.accentGreen,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: 'Shizuku (Best)'),
                      Tab(text: 'Wireless ADB (Kadb)'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 230,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Shizuku
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Shizuku binds permanently via Android Binder IPC. Once allowed, permissions survive app switches and phone locks.',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
                          ),
                          const SizedBox(height: 14),
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
                                  widget.hasPermission
                                      ? Icons.check_circle_rounded
                                      : (widget.hasShizuku ? Icons.verified_user_rounded : Icons.info_outline_rounded),
                                  color: widget.hasPermission
                                      ? AppTheme.accentGreen
                                      : (widget.hasShizuku ? AppTheme.chargingCyan : AppTheme.amber),
                                  size: 26,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Shizuku Manager',
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      Text(
                                        widget.hasPermission
                                            ? 'Authorized & Active'
                                            : (widget.hasShizuku ? 'Ready to Authorize' : 'Launch Shizuku App'),
                                        style: TextStyle(
                                          color: widget.hasPermission
                                              ? AppTheme.accentGreen
                                              : (widget.hasShizuku ? AppTheme.chargingCyan : AppTheme.textMuted),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: widget.hasPermission || _isRequesting ? null : _handleShizukuAuthorize,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.accentGreen,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: Text(
                                    widget.hasPermission ? 'Active' : (_isRequesting ? '...' : 'Authorize'),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_shizukuMessage != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _shizukuMessage!,
                              style: TextStyle(
                                fontSize: 11,
                                color: _shizukuMessage!.startsWith('✓') ? AppTheme.accentGreen : AppTheme.crimson,
                              ),
                            ),
                          ],
                        ],
                      ),

                      // Tab 2: Kadb (Wireless ADB)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Direct pairing via Settings -> Developer Options -> Wireless Debugging:',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _portController,
                                  focusNode: _portFocus,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(5),
                                  ],
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                  decoration: InputDecoration(
                                    labelText: 'Port',
                                    labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                                    hintText: '37755',
                                    hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                    filled: true,
                                    fillColor: AppTheme.surfaceVariant,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                  ),
                                  onSubmitted: (_) => _codeFocus.requestFocus(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _codeController,
                                  focusNode: _codeFocus,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(6),
                                  ],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2.0,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: '6-Digit Code',
                                    labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                                    hintText: '123456',
                                    hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12, letterSpacing: 0),
                                    filled: true,
                                    fillColor: AppTheme.surfaceVariant,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                  ),
                                  onSubmitted: (_) => _handleKadbPair(),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 40,
                            child: ElevatedButton.icon(
                              onPressed: _isPairingKadb ? null : _handleKadbPair,
                              icon: _isPairingKadb
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                  : const Icon(Icons.wifi_tethering_rounded, size: 16),
                              label: Text(
                                _isPairingKadb ? 'Pairing...' : 'Pair Localhost Kadb',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.chargingCyan,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          if (_kadbMessage != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _kadbMessage!,
                              style: TextStyle(
                                fontSize: 11,
                                color: _kadbMessage!.startsWith('✓') ? AppTheme.accentGreen : AppTheme.crimson,
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
