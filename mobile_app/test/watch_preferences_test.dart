import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ov_watch_app/features/history/data/health_history_repository.dart';
import 'package:ov_watch_app/features/watch/application/watch_controller.dart';
import 'package:ov_watch_app/features/watch/domain/watch_preferences.dart';
import 'package:ov_watch_app/features/watch/domain/watch_snapshot.dart';
import 'package:ov_watch_app/features/watch/domain/watch_transport.dart';

void main() {
  const previousDevice = WatchDevice(
    name: 'Previous watch',
    address: 'AA:BB:CC:DD:EE:01',
  );
  const nextDevice = WatchDevice(
    name: 'Next watch',
    address: 'AA:BB:CC:DD:EE:02',
  );

  late _FakePreferencesRepository preferences;
  late _FakeHistoryRepository history;
  late _FakeWatchTransport transport;
  late WatchController controller;

  setUp(() {
    preferences = _FakePreferencesRepository();
    history = _FakeHistoryRepository();
    transport = _FakeWatchTransport();
    controller = WatchController(
      transport: transport,
      historyRepository: history,
      preferencesRepository: preferences,
    );
    controller.setAutoRefresh(false);
  });

  tearDown(() => controller.dispose());

  test(
    'loads persisted goal and preferred device without connecting',
    () async {
      preferences.value = const WatchPreferences(
        stepGoal: 12000,
        preferredDevice: previousDevice,
      );

      await controller.initialize();

      expect(controller.stepGoal, 12000);
      expect(controller.preferredDevice, same(previousDevice));
      expect(controller.connectedDevice, isNull);
      expect(controller.connectionStatus, WatchConnectionStatus.disconnected);
      expect(transport.connectRequests, isEmpty);
      expect(preferences.savedGoals, isEmpty);
      expect(preferences.savedDevices, isEmpty);
    },
  );

  test('uses defaults when no preferences have been saved', () async {
    await controller.initialize();

    expect(controller.stepGoal, 8000);
    expect(controller.preferredDevice, isNull);
  });

  test('updates the goal only after persistence succeeds', () async {
    await controller.initialize();
    preferences.goalSaveCompletion = Completer<void>();
    var notifications = 0;
    controller.addListener(() => notifications++);

    final saving = controller.updateStepGoal(15000);
    await _flushEvents();
    expect(preferences.savedGoals, [15000]);
    expect(controller.stepGoal, 8000);
    expect(notifications, 0);

    preferences.goalSaveCompletion!.complete();
    expect(await saving, isTrue);
    expect(controller.stepGoal, 15000);
    expect(preferences.value.stepGoal, 15000);
    expect(notifications, 1);
  });

  test('accepts the inclusive goal boundaries', () async {
    await controller.initialize();

    expect(await controller.updateStepGoal(1000), isTrue);
    expect(controller.stepGoal, 1000);
    expect(await controller.updateStepGoal(50000), isTrue);
    expect(controller.stepGoal, 50000);
    expect(preferences.savedGoals, [1000, 50000]);
  });

  test('rejects invalid goals without writing or changing state', () async {
    await controller.initialize();

    for (final invalid in [-1, 0, 999, 50001]) {
      expect(await controller.updateStepGoal(invalid), isFalse);
    }

    expect(controller.stepGoal, 8000);
    expect(preferences.savedGoals, isEmpty);
  });

  test('failed goal save keeps the old value and permits retry', () async {
    preferences.value = const WatchPreferences(stepGoal: 10000);
    await controller.initialize();
    preferences.goalSaveError = StateError('storage unavailable');

    expect(await controller.updateStepGoal(14000), isFalse);
    expect(controller.stepGoal, 10000);
    expect(preferences.value.stepGoal, 10000);
    expect(controller.errorMessage, contains('storage unavailable'));

    preferences.goalSaveError = null;
    expect(await controller.updateStepGoal(14000), isTrue);
    expect(controller.stepGoal, 14000);
    expect(preferences.value.stepGoal, 14000);
    expect(controller.errorMessage, isNull);
  });

  test(
    'remembers a selected device only after connection confirmation',
    () async {
      preferences.value = const WatchPreferences(
        preferredDevice: previousDevice,
      );
      await controller.initialize();

      await controller.connect(nextDevice);
      expect(transport.connectRequests, [nextDevice.address]);
      expect(controller.preferredDevice, same(previousDevice));
      expect(preferences.savedDevices, isEmpty);

      for (final state in [
        WatchLinkState.connecting,
        WatchLinkState.reconnecting,
        WatchLinkState.failed,
      ]) {
        transport.emitLinkState(state);
        await _flushEvents();
        expect(controller.preferredDevice, same(previousDevice));
        expect(preferences.savedDevices, isEmpty);
      }

      await controller.connect(nextDevice);
      transport.emitLinkState(WatchLinkState.connected);
      await _flushEvents();
      expect(controller.preferredDevice, same(nextDevice));
      expect(preferences.savedDevices, [nextDevice]);
      expect(preferences.value.preferredDevice, same(nextDevice));
    },
  );

  test('does not save a preferred device when connection fails', () async {
    preferences.value = const WatchPreferences(preferredDevice: previousDevice);
    transport.connectError = const WatchTransportException('connection failed');
    await controller.initialize();

    await controller.connect(nextDevice);

    expect(controller.connectionStatus, WatchConnectionStatus.disconnected);
    expect(controller.preferredDevice, same(previousDevice));
    expect(preferences.savedDevices, isEmpty);
  });

  test('preferred device save failure does not break the connection', () async {
    preferences.deviceSaveError = StateError('cannot remember device');
    await controller.initialize();
    await controller.connect(nextDevice);

    transport.emitLinkState(WatchLinkState.connected);
    await _flushEvents();

    expect(controller.connectionStatus, WatchConnectionStatus.connected);
    expect(controller.connectedDevice, same(nextDevice));
    expect(controller.errorMessage, contains('cannot remember device'));
    expect(preferences.value.preferredDevice, isNull);
  });

  test(
    'restores the latest cached sample even outside today history',
    () async {
      final now = DateTime.now();
      final yesterday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(hours: 12));
      final older = _snapshot(
        yesterday.subtract(const Duration(hours: 1)),
        1200,
      );
      final newest = _snapshot(yesterday, 2400);
      history.samples.addAll([older, newest]);

      await controller.initialize();

      expect(controller.latest, same(newest));
      expect(controller.history, isEmpty);
      expect(controller.connectionStatus, WatchConnectionStatus.disconnected);
      expect(transport.connectRequests, isEmpty);
      expect(history.savedSamples, isEmpty);
      expect(history.readLimits, [1, 50000]);
    },
  );

  test('does not restore expired samples removed by retention', () async {
    history.samples.add(
      _snapshot(DateTime.now().subtract(const Duration(days: 91)), 1000),
    );

    await controller.initialize();

    expect(controller.latest, isNull);
    expect(controller.history, isEmpty);
    expect(history.samples, isEmpty);
  });

  test('a late cache read cannot replace a newly received sample', () async {
    final cached = _snapshot(
      DateTime.now().subtract(const Duration(hours: 1)),
      3,
    );
    final live = _snapshot(DateTime.now(), 6);
    history.samples.add(cached);
    history.cacheReadCompletion = Completer<void>();

    final initializing = controller.initialize();
    await _flushEvents();
    expect(history.readLimits, [1]);
    transport.emitSnapshot(live);
    await _flushEvents();
    expect(controller.latest, same(live));

    history.cacheReadCompletion!.complete();
    await initializing;
    expect(controller.latest, same(live));
  });
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

WatchSnapshot _snapshot(DateTime time, int steps) => WatchSnapshot(
  capturedAt: time,
  watchTime: time,
  steps: steps,
  heartRate: 72,
  temperature: 25,
  humidity: 50,
);

class _FakePreferencesRepository implements WatchPreferencesRepository {
  WatchPreferences value = const WatchPreferences();
  final savedGoals = <int>[];
  final savedDevices = <WatchDevice>[];
  Completer<void>? goalSaveCompletion;
  Object? goalSaveError;
  Object? deviceSaveError;

  @override
  Future<WatchPreferences> loadPreferences() async => value;

  @override
  Future<void> saveStepGoal(int goal) async {
    savedGoals.add(goal);
    await goalSaveCompletion?.future;
    final error = goalSaveError;
    if (error != null) throw error;
    value = WatchPreferences(
      stepGoal: goal,
      preferredDevice: value.preferredDevice,
    );
  }

  @override
  Future<void> savePreferredDevice(WatchDevice device) async {
    savedDevices.add(device);
    final error = deviceSaveError;
    if (error != null) throw error;
    value = WatchPreferences(stepGoal: value.stepGoal, preferredDevice: device);
  }
}

class _FakeHistoryRepository implements HealthHistoryRepository {
  final samples = <WatchSnapshot>[];
  final savedSamples = <WatchSnapshot>[];
  final readLimits = <int>[];
  Completer<void>? cacheReadCompletion;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> pruneBefore(DateTime cutoff) async {
    samples.removeWhere((sample) => sample.capturedAt.isBefore(cutoff));
  }

  @override
  Future<List<WatchSnapshot>> recent({
    DateTime? since,
    int limit = 50000,
  }) async {
    readLimits.add(limit);
    final filtered =
        samples
            .where(
              (sample) => since == null || !sample.capturedAt.isBefore(since),
            )
            .toList()
          ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    final result = filtered.length <= limit
        ? filtered
        : filtered.sublist(filtered.length - limit);
    if (since == null && limit == 1) await cacheReadCompletion?.future;
    return result;
  }

  @override
  Future<void> save(WatchSnapshot snapshot) async {
    savedSamples.add(snapshot);
    samples.add(snapshot);
  }
}

class _FakeWatchTransport implements WatchTransport {
  final _snapshots = StreamController<WatchSnapshot>.broadcast();
  final _logs = StreamController<String>.broadcast();
  final _linkStates = StreamController<WatchLinkState>.broadcast();
  final connectRequests = <String>[];
  Object? connectError;
  bool _connected = false;

  @override
  bool get isConnected => _connected;
  @override
  Stream<WatchSnapshot> get snapshots => _snapshots.stream;
  @override
  Stream<String> get logs => _logs.stream;
  @override
  Stream<WatchLinkState> get linkStates => _linkStates.stream;

  void emitLinkState(WatchLinkState state) {
    _connected = state == WatchLinkState.connected;
    _linkStates.add(state);
  }

  void emitSnapshot(WatchSnapshot snapshot) => _snapshots.add(snapshot);

  @override
  Future<void> connect(String address) async {
    connectRequests.add(address);
    final error = connectError;
    if (error != null) throw error;
  }

  @override
  Future<void> disconnect() async => emitLinkState(WatchLinkState.disconnected);
  @override
  Future<List<WatchDevice>> pairedDevices() async => [];
  @override
  Future<void> requestSnapshot() async {}
  @override
  Future<void> syncClock(DateTime time) async {}
  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> dispose() async {
    await _snapshots.close();
    await _logs.close();
    await _linkStates.close();
  }
}
