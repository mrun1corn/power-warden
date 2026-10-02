import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ui/dashboard_screen.dart';
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

class PowerWardenApp extends StatelessWidget {
  const PowerWardenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PowerWarden',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const DashboardScreen(),
    );
  }
}
