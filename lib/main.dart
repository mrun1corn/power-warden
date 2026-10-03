import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/telemetry_service.dart';
import 'ui/dashboard_screen.dart';
import 'ui/setup_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.pureOledBackground,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const PowerWardenApp());
}

class PowerWardenApp extends StatefulWidget {
  const PowerWardenApp({super.key});

  @override
  State<PowerWardenApp> createState() => _PowerWardenAppState();
}

class _PowerWardenAppState extends State<PowerWardenApp> {
  final _telemetryService = TelemetryService();
  bool _isLoading = true;
  bool _hasCompletedSetup = false;

  @override
  void initState() {
    super.initState();
    _checkSetup();
  }

  Future<void> _checkSetup() async {
    final completed = await _telemetryService.getPrefBool('has_completed_setup', defaultValue: false);
    if (mounted) {
      setState(() {
        _hasCompletedSetup = completed;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PowerWarden',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: _isLoading
          ? const Scaffold(
              backgroundColor: Colors.black,
              body: Center(child: CircularProgressIndicator(color: AppTheme.accentGreen)),
            )
          : _hasCompletedSetup
              ? const DashboardScreen()
              : SetupScreen(
                  onSetupComplete: () {
                    setState(() => _hasCompletedSetup = true);
                  },
                ),
    );
  }
}
