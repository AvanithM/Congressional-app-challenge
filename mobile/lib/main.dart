// (USER)
import 'dart:async';

import 'package:congress_app/services/api.dart';
import 'package:flutter/material.dart';
import 'package:congress_app/app_theme.dart';
import 'package:congress_app/pages/app_shell.dart';

void main() {
  runApp(const MyApp());
  unawaited(
    Api.forCurrentPlatform().startServices().then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Could not start backend services: $error');
      },
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Check-in',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AppShell(),
    );
  }
}
