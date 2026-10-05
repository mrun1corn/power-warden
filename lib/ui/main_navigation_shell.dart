import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'theme.dart';

/// Top-level thumb-friendly Material 3 Navigation Shell for PowerWarden.
/// Provides one-handed ergonomic switching between Live Sentinel & Power History.
class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBg = isDark
        ? AppTheme.pureOledBackground
        : AppTheme.lightBackground;
    final surfaceBorder = isDark
        ? AppTheme.surfaceBorderDark
        : AppTheme.surfaceBorderLight;

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
          indicatorColor: AppTheme.accentGreen.withValues(alpha: isDark ? 0.2 : 0.15),
          elevation: 0,
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (index) {
            setState(() => _currentIndex = index);
          },
          destinations: [
            NavigationDestination(
              icon: Icon(
                Icons.shield_outlined,
                color: isDark ? AppTheme.textMuted : AppTheme.textMutedLight,
                size: 22,
              ),
              selectedIcon: const Icon(
                Icons.shield_rounded,
                color: AppTheme.accentGreen,
                size: 22,
              ),
              label: 'Sentinel',
            ),
            NavigationDestination(
              icon: Icon(
                Icons.history_rounded,
                color: isDark ? AppTheme.textMuted : AppTheme.textMutedLight,
                size: 22,
              ),
              selectedIcon: const Icon(
                Icons.history_rounded,
                color: AppTheme.accentGreen,
                size: 22,
              ),
              label: 'History',
            ),
          ],
        ),
      ),
    );
  }
}
