import 'package:flutter/material.dart';

import 'app.dart';
import 'features/history/data/health_history_repository.dart';
import 'features/watch/application/watch_controller.dart';
import 'features/watch/data/spp_watch_transport.dart';
import 'features/stopwatch/application/watch_stopwatch_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final historyRepository = SqliteHealthHistoryRepository();
  final transport = SppWatchTransport();
  final controller = WatchController(
    transport: transport,
    historyRepository: historyRepository,
    preferencesRepository: historyRepository,
  );
  final stopwatchController = WatchStopwatchController(
    watch: controller,
    transport: transport,
  );
  runApp(
    OVWatchApp(
      controller: controller,
      stopwatchController: stopwatchController,
    ),
  );
  controller.initialize();
  stopwatchController.initialize();
}
