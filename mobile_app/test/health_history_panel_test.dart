import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ov_watch_app/core/theme/app_theme.dart';
import 'package:ov_watch_app/features/history/data/health_history_repository.dart';
import 'package:ov_watch_app/features/history/presentation/health_history_panel.dart';
import 'package:ov_watch_app/features/watch/application/watch_controller.dart';
import 'package:ov_watch_app/features/watch/domain/watch_snapshot.dart';
import 'package:ov_watch_app/features/watch/domain/watch_transport.dart';

void main() {
  testWidgets('switches metric/range and shows a single observation honestly', (
    tester,
  ) async {
    final controller = _HistoryController([_sample(heartRate: 0)]);
    addTearDown(controller.dispose);
    await _pumpPanel(tester, controller);
    expect(find.textContaining('暂无有效心率'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('history-metric-temperature')));
    await tester.pumpAndSettle();
    expect(find.text('环境温度趋势'), findsOneWidget);
    expect(find.textContaining('尚不足以展示变化趋势'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('history-range-week')));
    await tester.pumpAndSettle();
    expect(controller.historyRange, HistoryRange.week);
    expect(controller.lastRange, HistoryRange.week);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only explicit export copies selected raw records to clipboard', (
    tester,
  ) async {
    final copies = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copies.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final controller = _HistoryController([_sample()]);
    addTearDown(controller.dispose);
    await _pumpPanel(tester, controller);
    expect(copies, isEmpty);
    final copy = find.byKey(const ValueKey('copy-health-csv'));
    await tester.scrollUntilVisible(copy, 400);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(copies, hasLength(1));
    expect(copies.single, contains('steps_cumulative'));
    expect(copies.single, isNot(contains('spo2')));
    expect(find.text('已复制 1 条记录，可粘贴到表格中'), findsOneWidget);
  });

  testWidgets('empty export is disabled', (tester) async {
    final controller = _HistoryController([]);
    addTearDown(controller.dispose);
    await _pumpPanel(tester, controller);
    final copy = find.byKey(const ValueKey('copy-health-csv'));
    await tester.scrollUntilVisible(copy, 400);
    expect(tester.widget<OutlinedButton>(copy).onPressed, isNull);
    expect(find.textContaining('这个时间范围还没有记录'), findsOneWidget);
  });

  testWidgets(
    'small screen and large text have no overflow including trend and records',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _HistoryController([
        _sample(minutesAgo: 2),
        _sample(minutesAgo: 1, heartRate: 90),
      ]);
      addTearDown(controller.dispose);
      await _pumpPanel(tester, controller, textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('copy-health-csv')),
        300,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpPanel(
  WidgetTester tester,
  WatchController controller, {
  double textScale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData.fromView(
        tester.view,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: HealthHistoryPanel(controller: controller)),
    ),
  ),
);

WatchSnapshot _sample({int heartRate = 80, int minutesAgo = 1}) =>
    WatchSnapshot(
      capturedAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
      watchTime: DateTime(2020, 1, 1),
      steps: 2345,
      heartRate: heartRate,
      temperature: 25,
      humidity: 40,
      spo2: 99,
    );

class _HistoryController extends WatchController {
  _HistoryController(List<WatchSnapshot> samples)
    : super(transport: _IdleTransport(), historyRepository: _IdleRepository()) {
    history = samples;
  }

  HistoryRange? lastRange;

  @override
  Future<void> selectHistoryRange(HistoryRange value) async {
    lastRange = value;
    historyRange = value;
    notifyListeners();
  }

  @override
  Future<void> refreshHistory() async {}
}

class _IdleTransport implements WatchTransport {
  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IdleRepository implements HealthHistoryRepository {
  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
