import 'package:flutter/material.dart';

import 'package:congress_app/pages/home_screen.dart';
import 'package:congress_app/pages/progress_screen.dart';
import 'package:congress_app/pages/settings_screen.dart';
import 'package:congress_app/pages/goals_screen.dart';
import 'package:congress_app/services/api.dart';
import 'package:congress_app/services/notification.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.progressApi, this.notificationService});

  final Api? progressApi;
  final NotificationService? notificationService;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  int _progressRefreshTrigger = 0;
  final List<MapEntry<String, int>> _goals = [];

  static const _titles = ['Home', 'Goals', 'Progress', 'Settings'];

  void _updateGoals(List<MapEntry<String, int>> goals) {
    setState(() {
      _goals
        ..clear()
        ..addAll(goals);
    });
  }

  void _addFollowupGoals(List<MapEntry<String, int>> goals) {
    setState(() {
      _goals.addAll(goals);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_selectedIndex])),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          HomeScreen(
            onGoalsUpdated: _updateGoals,
            onFollowupGoalsAdded: _addFollowupGoals,
            notificationService: widget.notificationService,
          ),
          GoalsScreen(
            goals: _goals,
            notificationService: widget.notificationService,
          ),
          ProgressScreen(
            api: widget.progressApi,
            refreshTrigger: _progressRefreshTrigger,
          ),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
            if (index == 2) {
              _progressRefreshTrigger++;
            }
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag),
            label: 'Goals',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
