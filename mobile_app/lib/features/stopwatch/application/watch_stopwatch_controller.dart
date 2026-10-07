import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../watch/application/watch_controller.dart';
import '../data/stopwatch_repository.dart';
import '../domain/watch_companion.dart';

enum StopwatchSupport { disconnected, checking, supported, unsupported, failed }

class WatchStopwatchController extends ChangeNotifier {
  WatchStopwatchController({
    required WatchController watch,
    required WatchCompanionTransport transport,
    StopwatchRepository? repository,
    this.pollInterval = const Duration(seconds: 2),
  }) : _watch = watch,
       _transport = transport,
       _repository = repository ?? SqliteStopwatchRepository();

  final WatchController _watch;
  final WatchCompanionTransport _transport;
  final StopwatchRepository _repository;
  final Duration pollInterval;
  bool _initialized = false;
  bool _disposed = false;
  bool _visible = false;
  bool _active = true;
  bool _wasConnected = false;
  String? _address;
  int _generation = 0;
  int _readGeneration = 0;
  Timer? _timer;

  StopwatchSupport support = StopwatchSupport.disconnected;
  WatchCapabilities? capabilities;
  WatchStopwatchSnapshot? snapshot;
  DateTime? updatedAt;
  DateTime? historySyncedAt;
  List<StopwatchRecord> records = const [];
  StopwatchTag? tagFilter;
  String? errorMessage;
  bool busy = false;
  bool loadingHistory = true;
  String? get deviceName => _watch.connectedDevice?.name;
  bool get connected =>
      _watch.connectionStatus == WatchConnectionStatus.connected;
  bool get canSyncHistory => connected && capabilities?.stopwatchLog == true;
  Iterable<StopwatchRecord> get filteredRecords => tagFilter == null
      ? records
      : records.where((record) => record.tag == tagFilter);

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    _watch.addListener(_onWatchChanged);
    _onWatchChanged();
    await refreshLocalHistory();
  }

  Future<void> refreshLocalHistory() async {
    final read = ++_readGeneration;
    try {
      final saved = await _repository.recent();
      if (_disposed || read != _readGeneration) return;
      records = saved;
    } catch (error) {
      if (!_disposed && read == _readGeneration) {
        errorMessage = '读取计时历史失败：$error';
      }
    } finally {
      if (!_disposed && read == _readGeneration) {
        loadingHistory = false;
        notifyListeners();
      }
    }
  }

  void _onWatchChanged() {
    final nowConnected = connected;
    final address = _watch.connectedDevice?.address;
    if (nowConnected == _wasConnected && address == _address) return;
    _wasConnected = nowConnected;
    _address = address;
    _generation++;
    _timer?.cancel();
    busy = false;
    snapshot = null;
    updatedAt = null;
    historySyncedAt = null;
    capabilities = null;
    errorMessage = null;
    support = nowConnected && address != null
        ? StopwatchSupport.checking
        : StopwatchSupport.disconnected;
    notifyListeners();
    if (support == StopwatchSupport.checking) unawaited(_probe(_generation));
  }

  bool _current(int generation) =>
      !_disposed && generation == _generation && connected && _address != null;

  /// Explicit user refresh only; legacy firmware is not repeatedly probed.
  Future<void> refreshCapabilities() async {
    if (busy || !connected || _address == null || _disposed) return;
    support = StopwatchSupport.checking;
    notifyListeners();
    await _probe(_generation);
  }

  Future<void> _probe(int generation) async {
    busy = true;
    try {
      final result = await _transport.requestCapabilities();
      if (!_current(generation)) return;
      capabilities = result;
      support = result?.stopwatch == true
          ? StopwatchSupport.supported
          : StopwatchSupport.unsupported;
    } catch (error) {
      if (!_current(generation)) return;
      support = StopwatchSupport.failed;
      errorMessage = '检测手表计时能力失败：$error';
    } finally {
      if (_current(generation)) {
        busy = false;
        notifyListeners();
      }
    }
    if (!_current(generation)) return;
    if (canSyncHistory && _active) await syncHistory();
    if (!_current(generation)) return;
    if (_visible && _active) await refreshStopwatch();
    _schedule();
  }

  void setVisible(bool value) {
    if (_visible == value || _disposed) return;
    _visible = value;
    _schedule();
    if (value && _active) unawaited(_refreshOpenedPage());
  }

  void setAppActive(bool value) {
    if (_active == value || _disposed) return;
    _active = value;
    _schedule();
    if (value && _visible) unawaited(_refreshOpenedPage());
  }

  Future<void> _refreshOpenedPage() async {
    final generation = _generation;
    await syncHistory();
    if (_current(generation)) await refreshStopwatch();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_disposed &&
        _active &&
        _visible &&
        support == StopwatchSupport.supported &&
        connected) {
      _timer = Timer.periodic(
        pollInterval,
        (_) => unawaited(refreshStopwatch()),
      );
    }
  }

  Future<void> refreshStopwatch() async {
    if (busy ||
        !_active ||
        !_visible ||
        support != StopwatchSupport.supported ||
        !connected) {
      return;
    }
    final generation = _generation;
    busy = true;
    try {
      final result = await _transport.requestStopwatch();
      if (!_current(generation)) return;
      final previous = snapshot;
      snapshot = result;
      updatedAt = DateTime.now();
      errorMessage = null;
      // A reset/finish on the watch, not a pause, makes an archive available.
      if (capabilities?.stopwatchLog == true &&
          previous != null &&
          (previous.boot != result.boot ||
              previous.sid != result.sid ||
              previous.state != WatchStopwatchState.idle &&
                  result.state == WatchStopwatchState.idle)) {
        await _syncLogs(generation);
      }
    } catch (error) {
      if (_current(generation)) errorMessage = '读取秒表失败：$error';
    } finally {
      if (_current(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> syncHistory() async {
    if (busy || !canSyncHistory || !_active) return;
    final generation = _generation;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _syncLogs(generation);
    } catch (error) {
      if (_current(generation)) errorMessage = '同步计时历史失败：$error';
    } finally {
      if (_current(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _syncLogs(int generation) async {
    final address = _address!;
    final name = deviceName ?? 'OV-Watch';
    var after = 0;
    int? boot;
    final count = math.min(capabilities?.logCapacity ?? 0, 8);
    for (var i = 0; i < count; i++) {
      if (!_current(generation) || !_active) return;
      final entry = await _transport.requestStopwatchLog(afterSid: after);
      if (!_current(generation) || !_active) return;
      if (boot != null && entry.boot != boot) {
        throw const FormatException('手表在同步期间重启，请重新同步');
      }
      boot = entry.boot;
      if (entry.isEmpty) break;
      if (entry.sid! <= after) throw const FormatException('手表历史顺序异常');
      await _repository.upsert(
        StopwatchRecord(
          deviceAddress: address,
          deviceName: name,
          boot: entry.boot,
          sid: entry.sid!,
          endedAt: entry.endedAt!,
          durationMs: entry.durationMs!,
          importedAt: DateTime.now(),
        ),
      );
      if (!_current(generation)) return;
      after = entry.sid!;
      if (!entry.more) break;
    }
    if (!_current(generation)) return;
    historySyncedAt = DateTime.now();
    await refreshLocalHistory();
  }

  void setTagFilter(StopwatchTag? value) {
    tagFilter = value;
    notifyListeners();
  }

  Future<bool> annotate(
    StopwatchRecord record,
    StopwatchTag tag,
    String note,
  ) async {
    try {
      await _repository.annotate(record.key, tag, note);
      await refreshLocalHistory();
      return !_disposed;
    } catch (error) {
      if (!_disposed) {
        errorMessage = '保存备注失败：$error';
        notifyListeners();
      }
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    if (_initialized) _watch.removeListener(_onWatchChanged);
    unawaited(_repository.dispose());
    super.dispose();
  }
}
