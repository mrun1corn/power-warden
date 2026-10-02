import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/telemetry_service.dart';
import '../theme.dart';

/// Dual-Engine modal bottom sheet:
/// 1. Shizuku (Recommended, persistent Binder IPC)
/// 2. Wireless ADB with mDNS Auto-Port Detection and Notification Quick-Reply!
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
  int _discoveredPort = 0;
  Timer? _portPollingTimer;

  String? _shizukuMessage;
  String? _kadbMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _startPortDiscovery();
  }

  void _startPortDiscovery() {
    _telemetryService.startMdnsDiscovery();
    _portPollingTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final port = await _telemetryService.getDiscoveredPort();
      if (port > 0 && mounted) {
        setState(() {
          _discoveredPort = port;
          if (_portController.text.isEmpty) {
            _portController.text = '$port';
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _portPollingTimer?.cancel();
    _telemetryService.stopMdnsDiscovery();
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
    final port = int.tryParse(_portController.text.trim()) ?? _discoveredPort;
    final code = _codeController.text.trim();

    if (port <= 0 || code.isEmpty) {
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
                            'Shizuku or Auto-Detected Wireless ADB',
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
                      Tab(text: 'Shizuku (1-Tap)'),
                      Tab(text: 'Wireless ADB (Auto)'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 280,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Shizuku
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Shizuku is the easiest: it binds once through system Binder and never loses permission when switching apps.',
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
                                        'Shizuku Service',
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      Text(
                                        widget.hasPermission
                                            ? 'Authorized & Active'
                                            : (widget.hasShizuku ? 'Ready to Authorize' : 'Start Shizuku App'),
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

                      // Tab 2: Wireless ADB (Auto mDNS + Notification Reply)
                      SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.chargingCyan.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.chargingCyan.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.notifications_active_rounded, color: AppTheme.chargingCyan, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _discoveredPort > 0
                                          ? 'Port Auto-Detected: $_discoveredPort!\nSwipe down notification to type code without leaving Settings.'
                                          : 'Searching for port on Wi-Fi via mDNS...\nTurn on Wireless Debugging in Settings.',
                                      style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.3),
                                    ),
                                  ),
                                ],
                              ),
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
                                      hintText: _discoveredPort > 0 ? '$_discoveredPort' : 'e.g. 37755',
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
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 38,
                              child: ElevatedButton.icon(
                                onPressed: _isPairingKadb ? null : _handleKadbPair,
                                icon: _isPairingKadb
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                    : const Icon(Icons.wifi_tethering_rounded, size: 16),
                                label: Text(
                                  _isPairingKadb ? 'Pairing...' : 'Pair Now',
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
                              const SizedBox(height: 6),
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
