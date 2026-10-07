import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/shell/presentation/app_shell.dart';
import 'features/watch/application/watch_controller.dart';
import 'features/stopwatch/application/watch_stopwatch_controller.dart';

class OVWatchApp extends StatelessWidget {
  const OVWatchApp({
    super.key,
    required this.controller,
    this.stopwatchController,
  });

  final WatchController controller;
  final WatchStopwatchController? stopwatchController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OV Health',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: AppShell(
        controller: controller,
        stopwatchController: stopwatchController,
      ),
    );
  }
}
