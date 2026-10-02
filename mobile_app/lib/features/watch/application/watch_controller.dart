import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../history/data/health_history_repository.dart';
import '../domain/watch_snapshot.dart';
import '../domain/watch_transport.dart';

enum WatchConnectionStatus { disconnected, connecting, connected }

class WatchController extends ChangeNotifier {
  WatchController({
    required WatchTransport transport,
    required HealthHistoryRepository historyRepository,
  }) : _transport = transport,
       _historyRepository = historyRepository;

  final WatchTransport _transport;
  final HealthHistoryRepository _historyRepository;

  StreamSubscription<WatchSnapshot>? _snapshotSubscription;
  StreamSubscription<String>? _logSubscription;
  Timer? _pollTimer;
  DateTime? _lastPersistedAt;

  WatchConnectionStatus connectionStatus = WatchConnectionStatus.disconnected;
  List<WatchDevice> devices = const [];
  List<WatchSnapshot> history = const [];
  List<String> logs = const [];
  WatchSnapshot? latest;
  WatchDevice? connectedDevice;
  String? errorMessage;
  bool autoRefresh = true;
  bool busy = false;

  Future<void> initialize() async {
    _snapshotSubscription = _transport.snapshots.listen(
      _onSnapshot,
      onError: (Object error, StackTrace stackTrace) => _setError(error),
    );
    _logSubscription = _transport.logs.listen(_onLog);
    await Future.wait([refreshDevices(), refreshHistory()]);
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
      connectionStatus = WatchConnectionStatus.connected;
      _startPolling();
      await _transport.requestSnapshot();
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

  Future<void> refreshHistory() async {
    await _guard(() async {
      history = await _historyRepository.recent();
    }, showBusy: false);
  }

  Future<void> _onSnapshot(WatchSnapshot snapshot) async {
    latest = snapshot;
    errorMessage = null;
    notifyListeners();

    final previous = _lastPersistedAt;
    if (previous == null ||
        snapshot.capturedAt.difference(previous).inSeconds >= 60) {
      _lastPersistedAt = snapshot.capturedAt;
      await _historyRepository.save(snapshot);
      history = await _historyRepository.recent();
      notifyListeners();
    }
  }

  void _onLog(String line) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    logs = [...logs, '$timestamp  $line'];
    if (logs.length > 120) logs = logs.sublist(logs.length - 120);
    if (line == 'DISCONNECTED') {
      _pollTimer?.cancel();
      connectionStatus = WatchConnectionStatus.disconnected;
    }
    notifyListeners();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (!autoRefresh || connectionStatus != WatchConnectionStatus.connected) {
      return;
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        await _transport.requestSnapshot();
      } catch (error) {
        _setError(error);
      }
    });
  }

  Future<void> _guard(
    Future<void> Function() action, {
    bool showBusy = true,
  }) async {
    if (showBusy) busy = true;
    errorMessage = null;
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
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _snapshotSubscription?.cancel();
    _logSubscription?.cancel();
    unawaited(_transport.dispose());
    unawaited(_historyRepository.dispose());
    super.dispose();
  }
}
