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
  final bool hasKadb;
  final VoidCallback onAuthorized;

  const WirelessPairingSheet({
    super.key,
    required this.hasShizuku,
    required this.hasPermission,
    required this.hasKadb,
    required this.onAuthorized,
  });

  @override
  State<WirelessPairingSheet> createState() => _WirelessPairingSheetState();
}

class _WirelessPairingSheetState extends State<WirelessPairingSheet>
    with SingleTickerProviderStateMixin {
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
    // Do NOT stop mDNS discovery or dismiss the notification here!
    // The user needs the notification to remain visible in the status bar
    // while they are looking at the Wireless Debugging screen or pair dialog!
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
            ? '✓ Successfully Paired & Connected to Wireless ADB!'
            : '✗ Connection to port $port failed. Please verify Wireless Debugging is enabled.';
      });
      if (ok) {
        // Allow user to visibly see the success banner before closing modal
        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) {
          widget.onAuthorized();
        }
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
          height: MediaQuery.of(context).size.height * 0.72,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
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
                        color: AppTheme.accentGreen.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        color: AppTheme.accentGreen,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Elevated Diagnostics',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Shizuku or Auto-Detected Wireless ADB',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppTheme.textSecondary,
                      ),
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
                      Tab(text: 'Pair with Code'),
                      Tab(text: 'Shizuku API'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Wireless ADB (Auto mDNS + PIN/Port Input + Quick Redirect)
                      SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ENTER 6-DIGIT PIN & PORT',
                              style: TextStyle(
                                color: AppTheme.chargingCyan,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 8),
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
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: '5-Digit Port',
                                      labelStyle: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 11,
                                      ),
                                      hintText: _discoveredPort > 0
                                          ? '$_discoveredPort'
                                          : '37755',
                                      hintStyle: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 12,
                                      ),
                                      filled: true,
                                      fillColor: AppTheme.surfaceVariant,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                    onSubmitted: (_) =>
                                        _codeFocus.requestFocus(),
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
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2.0,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: '6-Digit Pairing PIN',
                                      labelStyle: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 11,
                                        letterSpacing: 0,
                                      ),
                                      hintText: '123456',
                                      hintStyle: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 14,
                                        letterSpacing: 0,
                                      ),
                                      filled: true,
                                      fillColor: AppTheme.surfaceVariant,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                    onSubmitted: (_) => _handleKadbPair(),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 42,
                              child: ElevatedButton.icon(
                                onPressed: _isPairingKadb
                                    ? null
                                    : _handleKadbPair,
                                icon: _isPairingKadb
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.black,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.link_rounded,
                                        size: 18,
                                      ),
                                label: Text(
                                  _isPairingKadb
                                      ? 'Pairing with localhost...'
                                      : 'Pair & Connect',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.accentGreen,
                                  foregroundColor: Colors.black,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            if (_kadbMessage != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: (_kadbMessage!.startsWith('✓')
                                          ? AppTheme.accentGreen
                                          : AppTheme.crimson)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _kadbMessage!,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: _kadbMessage!.startsWith('✓')
                                        ? AppTheme.accentGreen
                                        : AppTheme.crimson,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Divider(color: AppTheme.surfaceBorder, height: 1),
                            const SizedBox(height: 14),
                            // Quick Instructions & Direct Android Settings Link
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.surfaceBorder,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.help_outline_rounded,
                                        color: AppTheme.chargingCyan,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _discoveredPort > 0
                                              ? 'Port Auto-Detected: $_discoveredPort'
                                              : 'How to find your Pairing Code & Port',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    '1. Open Wireless Debugging in Developer Options.\n2. Tap "Pair device with pairing code".\n3. Enter the 6-digit code (PIN) and port into the fields above.',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 11,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 36,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _telemetryService
                                          .openWirelessDebuggingSettings(),
                                      icon: const Icon(
                                        Icons.open_in_new_rounded,
                                        size: 14,
                                      ),
                                      label: const Text(
                                        'Open Wireless Debugging Settings',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppTheme.chargingCyan,
                                        side: BorderSide(
                                          color: AppTheme.chargingCyan
                                              .withValues(alpha: 0.4),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Tab 2: Shizuku
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Shizuku binds permanently via Android Binder IPC. Once allowed, permissions survive app switches and phone locks.',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                              height: 1.4,
                            ),
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
                                      : (widget.hasShizuku
                                            ? Icons.verified_user_rounded
                                            : Icons.info_outline_rounded),
                                  color: widget.hasPermission
                                      ? AppTheme.accentGreen
                                      : (widget.hasShizuku
                                            ? AppTheme.chargingCyan
                                            : AppTheme.amber),
                                  size: 26,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Shizuku Service',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        widget.hasPermission
                                            ? 'Authorized & Active'
                                            : (widget.hasShizuku
                                                  ? 'Ready to Authorize'
                                                  : 'Start Shizuku App'),
                                        style: TextStyle(
                                          color: widget.hasPermission
                                              ? AppTheme.accentGreen
                                              : (widget.hasShizuku
                                                    ? AppTheme.chargingCyan
                                                    : AppTheme.textMuted),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed:
                                      widget.hasPermission || _isRequesting
                                      ? null
                                      : _handleShizukuAuthorize,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.accentGreen,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: Text(
                                    widget.hasPermission
                                        ? 'Active'
                                        : (_isRequesting ? '...' : 'Authorize'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
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
                                color: _shizukuMessage!.startsWith('✓')
                                    ? AppTheme.accentGreen
                                    : AppTheme.crimson,
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
      );
  }
}
