import 'package:flutter/material.dart';

import 'app.dart';
import 'features/history/data/health_history_repository.dart';
import 'features/watch/application/watch_controller.dart';
import 'features/watch/data/spp_watch_transport.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = WatchController(
    transport: SppWatchTransport(),
    historyRepository: SqliteHealthHistoryRepository(),
  );
  runApp(OVWatchApp(controller: controller));
  controller.initialize();
}
