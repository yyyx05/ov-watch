import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ov_watch_app/core/theme/app_theme.dart';
import 'package:ov_watch_app/features/history/data/health_history_repository.dart';
import 'package:ov_watch_app/features/history/domain/health_summary.dart';
import 'package:ov_watch_app/features/settings/presentation/step_goal_dialog.dart';
import 'package:ov_watch_app/features/shell/presentation/app_shell.dart';
import 'package:ov_watch_app/features/stopwatch/application/watch_stopwatch_controller.dart';
import 'package:ov_watch_app/features/stopwatch/data/stopwatch_repository.dart';
import 'package:ov_watch_app/features/stopwatch/domain/watch_companion.dart';
import 'package:ov_watch_app/features/watch/application/watch_controller.dart';
import 'package:ov_watch_app/features/watch/domain/watch_preferences.dart';
import 'package:ov_watch_app/features/watch/domain/watch_snapshot.dart';
import 'package:ov_watch_app/features/watch/domain/watch_transport.dart';

// Optional, explicitly labelled preview output, not a golden or a baseline.
// Example: OV_CAPTURE_UI=D:\DevTools\Outputs flutter test test/app_shell_test.dart
final _captureDirectory = Platform.environment['OV_CAPTURE_UI'];
bool _previewFontLoaded = false;

void main() {
  for (final textScale in [1.0, 1.8]) {
    testWidgets('320px home supports text scale $textScale without overflow', (
      tester,
    ) async {
      await _pumpApp(tester, size: const Size(320, 780), textScale: textScale);
      expect(find.text('OV Health'), findsOneWidget);
      expect(find.text('今日步数'), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(tester.takeException(), isNull);

      final homeScroll = find.byType(CustomScrollView).hitTestable();
      await tester.scrollUntilVisible(
        find.text('环境湿度'),
        350,
        scrollable: find.descendant(
          of: homeScroll,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('环境湿度'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'whole app navigates health, four history metrics and timer logs',
    (tester) async {
      final fixture = await _pumpApp(tester);
      expect(find.text('今日步数'), findsOneWidget);
      expect(find.textContaining('离线查看'), findsOneWidget);

      await _navigate(tester, '历史');
      expect(find.text('健康历史'), findsOneWidget);
      for (final metric in HealthMetric.values) {
        final chip = find.byKey(ValueKey('history-metric-${metric.name}'));
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
        expect(
          find.text(metric == HealthMetric.steps ? '记录步数合计' : '采样平均'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.text('计时记录'));
      await tester.pumpAndSettle();
      expect(find.text('计时历史'), findsOneWidget);
      expect(find.textContaining('6 段记录'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(ChoiceChip, '学习'));
      await tester.pumpAndSettle();
      expect(fixture.stopwatch.tagFilter, StopwatchTag.study);
      expect(find.textContaining('3 段记录'), findsOneWidget);

      await _navigate(tester, '计时');
      expect(find.text('每一段投入，都值得记录'), findsOneWidget);
      expect(find.text('手表未连接'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('goal edit from My page persists and updates the home goal', (
    tester,
  ) async {
    final fixture = await _pumpApp(tester);
    await _navigate(tester, '我的');
    await tester.tap(find.text('每日步数目标'));
    await tester.pumpAndSettle();
    expect(find.byType(StepGoalDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), '12000');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(fixture.preferences.goal, 12000);
    expect(find.textContaining('12000 步 · 根据自己的日常安排设置'), findsOneWidget);
    await _navigate(tester, '健康');
    expect(find.textContaining('目标 12000 步'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'device page filters unrelated paired devices and can reveal them',
    (tester) async {
      final fixture = await _pumpApp(tester);
      await _navigate(tester, '设备');

      expect(fixture.transport.deviceReads, 1);
      expect(find.text('KT6368A-SPP-2.1'), findsOneWidget);
      expect(find.text('OV-Watch Demo'), findsOneWidget);
      expect(find.text('Demo headphones'), findsNothing);
      await tester.tap(find.text('显示其他已配对设备'));
      await tester.pumpAndSettle();
      expect(find.text('Demo headphones'), findsOneWidget);

      await tester.tap(find.text('显示其他已配对设备'));
      await tester.pumpAndSettle();
      expect(find.text('Demo headphones'), findsNothing);
      expect(fixture.transport.connectRequests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('renders labelled demo previews when explicitly requested', (
    tester,
  ) async {
    await tester.runAsync(_loadPreviewFonts);
    final fixture = await _pumpApp(
      tester,
      size: const Size(430, 1100),
      showDemoLabel: true,
    );
    expect(find.text('演示数据 · 非真机'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, fixture.captureKey, 'OV-Health-0.2.0-demo-home.png');

    await _navigate(tester, '历史');
    expect(find.text('健康历史'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(
      tester,
      fixture.captureKey,
      'OV-Health-0.2.0-demo-history.png',
    );
    await tester.tap(find.text('计时记录'));
    await tester.pumpAndSettle();
    expect(find.text('计时历史'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(
      tester,
      fixture.captureKey,
      'OV-Health-0.2.0-demo-stopwatch.png',
    );
  }, skip: _captureDirectory == null || _captureDirectory!.isEmpty);
}

Future<void> _navigate(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<_AppFixture> _pumpApp(
  WidgetTester tester, {
  Size size = const Size(430, 960),
  double textScale = 1,
  bool showDemoLabel = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  final fixture = _AppFixture();
  await fixture.watch.initialize();
  await fixture.stopwatch.initialize();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.stopwatch.dispose();
    fixture.watch.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  var theme = AppTheme.light();
  if (_previewFontLoaded) {
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'OVPreview'),
      primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'OVPreview'),
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: RepaintBoundary(
          key: fixture.captureKey,
          child: Column(
            children: [
              if (showDemoLabel)
                Material(
                  color: const Color(0xFFE9EDF5),
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        '演示数据 · 非真机',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: const Color(0xFF52627B),
                          fontFamily: _previewFontLoaded ? 'OVPreview' : null,
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(child: child!),
            ],
          ),
        ),
      ),
      home: AppShell(
        controller: fixture.watch,
        stopwatchController: fixture.stopwatch,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

Future<void> _loadPreviewFonts() async {
  // Use locally installed display fonts only for opt-in human-facing previews.
  // Ordinary tests remain independent of host fonts and screenshot files.
  final fonts = <String, String>{
    'OVPreview':
        '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\Fonts\\msyh.ttc',
    'MaterialIcons':
        r'D:\DevTools\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
  };
  for (final entry in fonts.entries) {
    final file = File(entry.value);
    if (!await file.exists()) continue;
    final loader = FontLoader(
      entry.key,
    )..addFont(file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
    await loader.load();
    if (entry.key == 'OVPreview') _previewFontLoaded = true;
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(_captureDirectory!);
      await directory.create(recursive: true);
      await File(
        '${directory.path}${Platform.pathSeparator}$name',
      ).writeAsBytes(
        bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}

class _AppFixture {
  _AppFixture() {
    watch = WatchController(
      transport: transport,
      historyRepository: _DemoHistoryRepository(),
      preferencesRepository: preferences,
    )..setAutoRefresh(false);
    stopwatch = WatchStopwatchController(
      watch: watch,
      transport: transport,
      repository: _DemoStopwatchRepository(),
    );
  }

  final captureKey = GlobalKey();
  final transport = _DemoTransport();
  final preferences = _DemoPreferencesRepository();
  late final WatchController watch;
  late final WatchStopwatchController stopwatch;
}

class _DemoPreferencesRepository implements WatchPreferencesRepository {
  int goal = 8000;
  @override
  Future<WatchPreferences> loadPreferences() async =>
      WatchPreferences(stepGoal: goal);
  @override
  Future<void> saveStepGoal(int value) async => goal = value;
  @override
  Future<void> savePreferredDevice(WatchDevice device) async {}
}

class _DemoHistoryRepository implements HealthHistoryRepository {
  final List<WatchSnapshot> samples = [
    for (var i = 0; i < 8; i++)
      WatchSnapshot(
        capturedAt: DateTime.now().subtract(Duration(minutes: 36 - i * 5)),
        watchTime: DateTime.now().subtract(Duration(minutes: 36 - i * 5)),
        steps: 4200 + i * 320,
        heartRate: [68, 70, 74, 72, 78, 76, 73, 71][i],
        temperature: 24 + i ~/ 3,
        humidity: 48 + i,
      ),
  ];
  @override
  Future<List<WatchSnapshot>> recent({
    DateTime? since,
    int limit = 50000,
  }) async {
    final filtered = samples
        .where((sample) => since == null || !sample.capturedAt.isBefore(since))
        .toList();
    return filtered.length > limit
        ? filtered.sublist(filtered.length - limit)
        : filtered;
  }

  @override
  Future<void> save(WatchSnapshot snapshot) async => samples.add(snapshot);
  @override
  Future<void> pruneBefore(DateTime cutoff) async {}
  @override
  Future<void> dispose() async {}
}

class _DemoStopwatchRepository implements StopwatchRepository {
  final records = [
    for (var i = 1; i <= 6; i++)
      StopwatchRecord(
        deviceAddress: '00:00:00:00:00:01',
        deviceName: 'OV-Watch Demo',
        boot: 1,
        sid: i,
        endedAt: DateTime.now().subtract(Duration(hours: i)),
        durationMs: (15 + i * 5) * 60000,
        importedAt: DateTime.now(),
        tag: i.isEven ? StopwatchTag.exercise : StopwatchTag.study,
        note: '演示计时 $i',
      ),
  ];
  @override
  Future<List<StopwatchRecord>> recent() async => List.of(records);
  @override
  Future<void> upsert(StopwatchRecord record) async => records.add(record);
  @override
  Future<void> annotate(String key, StopwatchTag tag, String note) async {}
  @override
  Future<void> dispose() async {}
}

class _DemoTransport implements WatchTransport, WatchCompanionTransport {
  final _snapshots = StreamController<WatchSnapshot>.broadcast();
  final _logs = StreamController<String>.broadcast();
  final _states = StreamController<WatchLinkState>.broadcast();
  final connectRequests = <String>[];
  int deviceReads = 0;
  @override
  bool get isConnected => false;
  @override
  Stream<WatchSnapshot> get snapshots => _snapshots.stream;
  @override
  Stream<String> get logs => _logs.stream;
  @override
  Stream<WatchLinkState> get linkStates => _states.stream;
  @override
  Future<List<WatchDevice>> pairedDevices() async {
    deviceReads++;
    return const [
      WatchDevice(name: 'KT6368A-SPP-2.1', address: '00:00:00:00:00:01'),
      WatchDevice(name: 'OV-Watch Demo', address: '00:00:00:00:00:02'),
      WatchDevice(name: 'Demo headphones', address: '00:00:00:00:00:03'),
    ];
  }

  @override
  Future<void> connect(String address) async => connectRequests.add(address);
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> requestSnapshot() async {}
  @override
  Future<void> syncClock(DateTime time) async {}
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<WatchCapabilities?> requestCapabilities() async => null;
  @override
  Future<WatchStopwatchSnapshot> requestStopwatch() async =>
      throw StateError('Offline demo must not request a stopwatch');
  @override
  Future<WatchStopwatchLog> requestStopwatchLog({int afterSid = 0}) async =>
      throw StateError('Offline demo must not request logs');
  @override
  Future<void> dispose() async {
    await _snapshots.close();
    await _logs.close();
    await _states.close();
  }
}
