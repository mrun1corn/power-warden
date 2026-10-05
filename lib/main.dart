import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/telemetry_service.dart';
import 'ui/main_navigation_shell.dart';
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

  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

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
    final completed = await _telemetryService.getPrefBool(
      'has_completed_setup',
      defaultValue: false,
    );
    final isLight = await _telemetryService.getPrefBool(
      'is_light_mode',
      defaultValue: false,
    );
    PowerWardenApp.themeModeNotifier.value = isLight
        ? ThemeMode.light
        : ThemeMode.dark;

    if (mounted) {
      setState(() {
        _hasCompletedSetup = completed;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: PowerWardenApp.themeModeNotifier,
      builder: (context, currentMode, _) {
        final isLight = currentMode == ThemeMode.light;
        final overlayStyle = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: isLight
              ? AppTheme.lightBackground
              : AppTheme.pureOledBackground,
          systemNavigationBarIconBrightness: isLight
              ? Brightness.dark
              : Brightness.light,
        );

        return MaterialApp(
          title: 'PowerWarden',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          builder: (context, child) {
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: overlayStyle,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: _isLoading
              ? const Scaffold(
                  backgroundColor: Colors.black,
                  body: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.accentGreen,
                    ),
                  ),
                )
              : _hasCompletedSetup
              ? const MainNavigationShell()
              : SetupScreen(
                  onSetupComplete: () {
                    setState(() => _hasCompletedSetup = true);
                  },
                ),
        );
      },
    );
  }
}
