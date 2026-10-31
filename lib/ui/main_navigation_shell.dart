import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/database/database.dart';
import 'dashboard_screen.dart';
import 'engine_screen.dart';
import 'history_screen.dart';
import 'incidents_screen.dart';
import 'theme.dart';

/// Top-level thumb-friendly Material 3 Navigation Shell for PowerWarden.
/// One-handed ergonomic switching between Sentinel, Incidents, History & Settings.
class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    _StandaloneIncidentsScreen(),
    HistoryScreen(),
    EngineScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBg = isDark ? AppTheme.pureOledBackground : AppTheme.lightBackground;
    final surfaceBorder =
        isDark ? AppTheme.surfaceBorderDark : AppTheme.surfaceBorderLight;
    final unselected = isDark ? AppTheme.textMuted : AppTheme.textMutedLight;

    return Scaffold(
      backgroundColor: navBg,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: navBg,
          border: Border(
            top: BorderSide(
              color: surfaceBorder.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          backgroundColor: navBg,
          surfaceTintColor: Colors.transparent,
          indicatorColor:
              AppTheme.accentGreen.withValues(alpha: isDark ? 0.2 : 0.15),
          elevation: 0,
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (index) {
            HapticFeedback.selectionClick();
            setState(() => _currentIndex = index);
          },
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.shield_outlined, color: unselected, size: 22),
              selectedIcon: const Icon(
                Icons.shield_rounded,
                color: AppTheme.accentGreen,
                size: 22,
              ),
              label: 'Sentinel',
            ),
            NavigationDestination(
              icon: Icon(Icons.report_outlined, color: unselected, size: 22),
              selectedIcon: const Icon(
                Icons.report_rounded,
                color: AppTheme.accentGreen,
                size: 22,
              ),
              label: 'Incidents',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_rounded, color: unselected, size: 22),
              selectedIcon: const Icon(
                Icons.history_rounded,
                color: AppTheme.accentGreen,
                size: 22,
              ),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined, color: unselected, size: 22),
              selectedIcon: const Icon(
                Icons.settings_rounded,
                color: AppTheme.accentGreen,
                size: 22,
              ),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

/// Incidents tab bound to the shared AppDatabase anomaly store.
class _StandaloneIncidentsScreen extends StatelessWidget {
  const _StandaloneIncidentsScreen();

  @override
  Widget build(BuildContext context) {
    final db = AppDatabase();
    return IncidentsScreen(
      loadIncidents: () => db.getRecentAnomalies(limit: 100),
    );
  }
}
