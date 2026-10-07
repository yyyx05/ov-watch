import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ov_watch_app/features/history/data/health_history_repository.dart';
import 'package:ov_watch_app/features/watch/application/watch_controller.dart';
import 'package:ov_watch_app/features/watch/domain/watch_snapshot.dart';
import 'package:ov_watch_app/features/watch/domain/watch_transport.dart';

void main() {
  test('reflects reconnect states and preserves the selected device', () async {
    final transport = _FakeWatchTransport();
    final controller = WatchController(
      transport: transport,
      historyRepository: _FakeHistoryRepository(),
    );
    await controller.initialize();

    const device = WatchDevice(name: 'OV-Watch', address: 'AA:BB:CC:DD:EE:FF');
    await controller.connect(device);
    expect(controller.connectionStatus, WatchConnectionStatus.connecting);

    transport.emitLinkState(WatchLinkState.reconnecting);
    await _flushEvents();
    expect(controller.connectionStatus, WatchConnectionStatus.reconnecting);
    expect(controller.connectedDevice, same(device));

    transport.emitLinkState(WatchLinkState.connected);
    await _flushEvents();
    expect(controller.connectionStatus, WatchConnectionStatus.connected);
    expect(transport.snapshotRequests, 1);

    transport.emitLinkState(WatchLinkState.failed);
    await _flushEvents();
    expect(controller.connectionStatus, WatchConnectionStatus.failed);
    expect(controller.errorMessage, contains('自动重连失败'));

    controller.dispose();
  });

  test('pauses polling in background and resumes in foreground', () async {
    final transport = _FakeWatchTransport();
    final controller = WatchController(
      transport: transport,
      historyRepository: _FakeHistoryRepository(),
      pollInterval: const Duration(milliseconds: 20),
    );
    await controller.initialize();
    await controller.connect(transport.devices.single);
    transport.emitLinkState(WatchLinkState.connected);
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(transport.snapshotRequests, greaterThanOrEqualTo(2));

    controller.setAppActive(false);
    final pausedCount = transport.snapshotRequests;
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(transport.snapshotRequests, pausedCount);

    controller.setAppActive(true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(transport.snapshotRequests, greaterThan(pausedCount));

    controller.dispose();
  });

  test(
    'clock sync ignores repeat taps and waits for acknowledgement',
    () async {
      final transport = _FakeWatchTransport();
      transport.clockSyncCompletion = Completer<void>();
      final controller = WatchController(
        transport: transport,
        historyRepository: _FakeHistoryRepository(),
        pollInterval: const Duration(milliseconds: 20),
      );
      await controller.initialize();
      await controller.connect(transport.devices.single);
      transport.emitLinkState(WatchLinkState.connected);
      await _flushEvents();

      final pendingSync = controller.syncClock();
      await controller.syncClock();
      await controller.requestNow();
      final pausedCount = transport.snapshotRequests;
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(transport.clockSyncRequests, 1);
      expect(transport.snapshotRequests, pausedCount);
      expect(controller.clockSyncStatus, ClockSyncStatus.syncing);
      expect(controller.clockSyncMessage, contains('等待手表确认'));

      transport.clockSyncCompletion!.complete();
      await pendingSync;
      expect(controller.clockSyncStatus, ClockSyncStatus.succeeded);
      expect(controller.clockSyncMessage, contains('手表已确认'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(transport.snapshotRequests, greaterThan(pausedCount));
      controller.dispose();
    },
  );

  test('clock sync failure is visible and allows retry', () async {
    final transport = _FakeWatchTransport();
    transport.clockSyncCompletion = Completer<void>();
    final controller = WatchController(
      transport: transport,
      historyRepository: _FakeHistoryRepository(),
    );
    await controller.initialize();
    transport.emitLinkState(WatchLinkState.connected);
    await _flushEvents();

    final pendingSync = controller.syncClock();
    transport.clockSyncCompletion!.completeError(
      const WatchTransportException('请先开启手表“同步APP”'),
    );
    await pendingSync;
    expect(controller.clockSyncStatus, ClockSyncStatus.failed);
    expect(controller.clockSyncMessage, contains('同步APP'));

    transport.clockSyncCompletion = null;
    await controller.syncClock();
    expect(transport.clockSyncRequests, 2);
    expect(controller.clockSyncStatus, ClockSyncStatus.succeeded);
    controller.dispose();
  });

  test('clock sync does not send commands while disconnected', () async {
    final transport = _FakeWatchTransport();
    final controller = WatchController(
      transport: transport,
      historyRepository: _FakeHistoryRepository(),
    );
    await controller.initialize();
    await controller.syncClock();
    expect(transport.clockSyncRequests, 0);
    expect(controller.clockSyncStatus, ClockSyncStatus.failed);
    expect(controller.clockSyncMessage, '请先连接手表');
    controller.dispose();
  });

  test('manual refresh does not pile up behind an ongoing sample', () async {
    final transport = _FakeWatchTransport();
    transport.snapshotCompletion = Completer<void>();
    final controller = WatchController(
      transport: transport,
      historyRepository: _FakeHistoryRepository(),
      pollInterval: const Duration(milliseconds: 20),
    );
    await controller.initialize();
    transport.emitLinkState(WatchLinkState.connected);
    await _flushEvents();
    await controller.requestNow();
    await controller.requestNow();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(transport.snapshotRequests, 1);
    transport.snapshotCompletion!.complete();
    await _flushEvents();
    controller.dispose();
  });

  test('disposing during clock sync does not restart polling', () async {
    final transport = _FakeWatchTransport();
    transport.clockSyncCompletion = Completer<void>();
    final controller = WatchController(
      transport: transport,
      historyRepository: _FakeHistoryRepository(),
      pollInterval: const Duration(milliseconds: 20),
    );
    await controller.initialize();
    transport.emitLinkState(WatchLinkState.connected);
    await _flushEvents();
    final pendingSync = controller.syncClock();
    controller.dispose();
    final requestCount = transport.snapshotRequests;
    transport.clockSyncCompletion!.completeError(
      const WatchTransportException('连接已断开'),
    );
    await pendingSync;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(transport.snapshotRequests, requestCount);
  });

  test(
    'switching watches clears clock status and ignores old completion',
    () async {
      final transport = _FakeWatchTransport();
      final controller = WatchController(
        transport: transport,
        historyRepository: _FakeHistoryRepository(),
      );
      await controller.initialize();
      transport.emitLinkState(WatchLinkState.connected);
      await _flushEvents();
      await controller.syncClock();
      expect(controller.clockSyncStatus, ClockSyncStatus.succeeded);

      await controller.connect(transport.devices.single);
      expect(controller.clockSyncStatus, ClockSyncStatus.idle);
      expect(controller.clockSyncMessage, isNull);
      transport.emitLinkState(WatchLinkState.connected);
      await _flushEvents();
      transport.clockSyncCompletion = Completer<void>();
      final oldSync = controller.syncClock();
      await controller.connect(
        const WatchDevice(name: 'Second watch', address: '11:22:33:44:55:66'),
      );
      transport.emitLinkState(WatchLinkState.connected);
      await _flushEvents();
      transport.clockSyncCompletion!.complete();
      await oldSync;
      expect(controller.clockSyncStatus, ClockSyncStatus.idle);
      expect(controller.clockSyncMessage, isNull);
      controller.dispose();
    },
  );
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

class _FakeWatchTransport implements WatchTransport {
  final _snapshots = StreamController<WatchSnapshot>.broadcast();
  final _logs = StreamController<String>.broadcast();
  final _linkStates = StreamController<WatchLinkState>.broadcast();

  final devices = const [
    WatchDevice(name: 'OV-Watch', address: 'AA:BB:CC:DD:EE:FF'),
  ];

  int snapshotRequests = 0;
  Completer<void>? snapshotCompletion;
  int clockSyncRequests = 0;
  Completer<void>? clockSyncCompletion;
  bool connected = false;

  @override
  bool get isConnected => connected;

  @override
  Stream<WatchLinkState> get linkStates => _linkStates.stream;

  @override
  Stream<String> get logs => _logs.stream;

  @override
  Stream<WatchSnapshot> get snapshots => _snapshots.stream;

  void emitLinkState(WatchLinkState state) {
    connected = state == WatchLinkState.connected;
    _linkStates.add(state);
  }

  @override
  Future<void> connect(String address) async {}

  @override
  Future<void> disconnect() async {
    emitLinkState(WatchLinkState.disconnected);
  }

  @override
  Future<void> dispose() async {
    await _snapshots.close();
    await _logs.close();
    await _linkStates.close();
  }

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<List<WatchDevice>> pairedDevices() async => devices;

  @override
  Future<void> requestSnapshot() async {
    snapshotRequests++;
    await snapshotCompletion?.future;
  }

  @override
  Future<void> syncClock(DateTime time) async {
    clockSyncRequests++;
    await clockSyncCompletion?.future;
  }
}

class _FakeHistoryRepository implements HealthHistoryRepository {
  final samples = <WatchSnapshot>[];

  @override
  Future<void> dispose() async {}

  @override
  Future<List<WatchSnapshot>> recent({
    DateTime? since,
    int limit = 50000,
  }) async {
    final filtered = since == null
        ? samples
        : samples
              .where((sample) => !sample.capturedAt.isBefore(since))
              .toList();
    return filtered.length <= limit
        ? List<WatchSnapshot>.of(filtered)
        : filtered.sublist(filtered.length - limit);
  }

  @override
  Future<void> pruneBefore(DateTime cutoff) async {
    samples.removeWhere((sample) => sample.capturedAt.isBefore(cutoff));
  }

  @override
  Future<void> save(WatchSnapshot snapshot) async {
    samples.add(snapshot);
  }
}
