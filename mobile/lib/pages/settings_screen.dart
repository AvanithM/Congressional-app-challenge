import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        const Card(
          child: ListTile(
            leading: Icon(Icons.notifications_outlined),
            title: Text('Reminders'),
            subtitle: Text(
              'Goal reminders are scheduled for 9:00 a.m. the day before '
              'a goal is due on Android and iOS.',
            ),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Privacy'),
            subtitle: Text(
              'Check-ins are processed by the configured backend and kept '
              'in its history.',
            ),
          ),
        ),
      ],
    );
  }
}
