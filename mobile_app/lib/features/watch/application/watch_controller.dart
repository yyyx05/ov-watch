import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../history/data/health_history_repository.dart';
import '../domain/watch_snapshot.dart';
import '../domain/watch_transport.dart';

enum WatchConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

enum HistoryRange {
  day('今日', Duration(days: 1)),
  week('7 天', Duration(days: 7)),
  month('30 天', Duration(days: 30));

  const HistoryRange(this.label, this.duration);

  final String label;
  final Duration duration;

  DateTime startAt(DateTime now) => switch (this) {
    HistoryRange.day => DateTime(now.year, now.month, now.day),
    HistoryRange.week || HistoryRange.month => now.subtract(duration),
  };
}

class WatchController extends ChangeNotifier {
  WatchController({
    required WatchTransport transport,
    required HealthHistoryRepository historyRepository,
    this.pollInterval = const Duration(seconds: 2),
    this.historyPersistInterval = const Duration(minutes: 1),
  }) : _transport = transport,
       _historyRepository = historyRepository;

  final WatchTransport _transport;
  final HealthHistoryRepository _historyRepository;
  final Duration pollInterval;
  final Duration historyPersistInterval;

  StreamSubscription<WatchSnapshot>? _snapshotSubscription;
  StreamSubscription<String>? _logSubscription;
  StreamSubscription<WatchLinkState>? _linkStateSubscription;
  Timer? _pollTimer;
  DateTime? _lastPersistedAt;
  bool _pollInFlight = false;
  bool _appActive = true;

  WatchConnectionStatus connectionStatus = WatchConnectionStatus.disconnected;
  List<WatchDevice> devices = const [];
  List<WatchSnapshot> history = const [];
  HistoryRange historyRange = HistoryRange.day;
  List<String> logs = const [];
  WatchSnapshot? latest;
  WatchDevice? connectedDevice;
  String? errorMessage;
  bool errorCanOpenSettings = false;
  bool autoRefresh = true;
  bool busy = false;

  Future<void> initialize() async {
    _snapshotSubscription = _transport.snapshots.listen(
      _onSnapshot,
      onError: (Object error, StackTrace stackTrace) => _setError(error),
    );
    _logSubscription = _transport.logs.listen(_onLog);
    _linkStateSubscription = _transport.linkStates.listen(_onLinkState);
    try {
      await _historyRepository.pruneBefore(
        DateTime.now().subtract(const Duration(days: 90)),
      );
    } catch (error) {
      _setError(error);
    }
    await refreshHistory();
  }

  Future<void> refreshDevices() async {
    await _guard(() async {
      devices = await _transport.pairedDevices();
    });
  }

  Future<void> connect(WatchDevice device) async {
    connectionStatus = WatchConnectionStatus.connecting;
    connectedDevice = device;
    errorMessage = null;
    notifyListeners();
    try {
      await _transport.connect(device.address);
    } catch (error) {
      connectionStatus = WatchConnectionStatus.disconnected;
      connectedDevice = null;
      _setError(error);
    } finally {
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    await _transport.disconnect();
    connectionStatus = WatchConnectionStatus.disconnected;
    connectedDevice = null;
    notifyListeners();
  }

  Future<void> requestNow() async {
    if (connectionStatus != WatchConnectionStatus.connected) {
      _setError(const WatchTransportException('手表尚未连接'));
      return;
    }
    await _guard(_transport.requestSnapshot);
  }

  Future<void> syncClock() async {
    await _guard(() => _transport.syncClock(DateTime.now()));
  }

  void setAutoRefresh(bool value) {
    autoRefresh = value;
    if (value) {
      _startPolling();
    } else {
      _pollTimer?.cancel();
    }
    notifyListeners();
  }

  void setAppActive(bool value) {
    if (_appActive == value) return;
    _appActive = value;
    if (value) {
      _startPolling();
      if (connectionStatus == WatchConnectionStatus.connected) {
        unawaited(_requestSnapshotQuietly());
      }
    } else {
      _pollTimer?.cancel();
    }
  }

  Future<void> openAppSettings() async {
    await _transport.openAppSettings();
  }

  Future<void> refreshHistory() async {
    await _guard(() async {
      history = await _historyRepository.recent(
        since: historyRange.startAt(DateTime.now()),
      );
    }, showBusy: false);
  }

  Future<void> selectHistoryRange(HistoryRange value) async {
    if (historyRange == value) return;
    historyRange = value;
    notifyListeners();
    await refreshHistory();
  }

  Future<void> _onSnapshot(WatchSnapshot snapshot) async {
    latest = snapshot;
    errorMessage = null;
    notifyListeners();

    try {
      final previous = _lastPersistedAt;
      if (previous == null ||
          snapshot.capturedAt.difference(previous) >= historyPersistInterval) {
        await _historyRepository.save(snapshot);
        _lastPersistedAt = snapshot.capturedAt;
        history = await _historyRepository.recent(
          since: historyRange.startAt(DateTime.now()),
        );
        notifyListeners();
      }
    } catch (error) {
      _setError(error);
    }
  }

  void _onLog(String line) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    logs = [...logs, '$timestamp  $line'];
    if (logs.length > 120) logs = logs.sublist(logs.length - 120);
    notifyListeners();
  }

  void _onLinkState(WatchLinkState state) {
    switch (state) {
      case WatchLinkState.disconnected:
        _pollTimer?.cancel();
        connectionStatus = WatchConnectionStatus.disconnected;
      case WatchLinkState.connecting:
        _pollTimer?.cancel();
        connectionStatus = WatchConnectionStatus.connecting;
      case WatchLinkState.connected:
        connectionStatus = WatchConnectionStatus.connected;
        errorMessage = null;
        errorCanOpenSettings = false;
        _startPolling();
        unawaited(_requestSnapshotQuietly());
      case WatchLinkState.reconnecting:
        _pollTimer?.cancel();
        connectionStatus = WatchConnectionStatus.reconnecting;
      case WatchLinkState.failed:
        _pollTimer?.cancel();
        connectionStatus = WatchConnectionStatus.failed;
        _setError(const WatchTransportException('自动重连失败，请确认手表蓝牙已开启后重试'));
        return;
    }
    notifyListeners();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (!autoRefresh ||
        !_appActive ||
        connectionStatus != WatchConnectionStatus.connected) {
      return;
    }
    _pollTimer = Timer.periodic(pollInterval, (_) => _requestSnapshotQuietly());
  }

  Future<void> _requestSnapshotQuietly() async {
    if (_pollInFlight ||
        !_appActive ||
        connectionStatus != WatchConnectionStatus.connected) {
      return;
    }
    _pollInFlight = true;
    try {
      await _transport.requestSnapshot();
    } catch (error) {
      _setError(error);
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _guard(
    Future<void> Function() action, {
    bool showBusy = true,
  }) async {
    if (showBusy) busy = true;
    errorMessage = null;
    errorCanOpenSettings = false;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _setError(error);
    } finally {
      if (showBusy) busy = false;
      notifyListeners();
    }
  }

  void _setError(Object error) {
    errorMessage = error.toString();
    errorCanOpenSettings =
        error is WatchTransportException && error.canOpenSettings;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _snapshotSubscription?.cancel();
    _logSubscription?.cancel();
    _linkStateSubscription?.cancel();
    unawaited(_transport.dispose());
    unawaited(_historyRepository.dispose());
    super.dispose();
  }
}
