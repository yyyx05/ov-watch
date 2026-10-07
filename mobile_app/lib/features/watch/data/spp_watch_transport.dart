import 'dart:async';

import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

import '../../stopwatch/domain/watch_companion.dart';
import '../domain/watch_snapshot.dart';
import '../domain/watch_transport.dart';
import 'legacy_ov_parser.dart';

class SppWatchTransport implements WatchTransport, WatchCompanionTransport {
  SppWatchTransport({
    this.responseTimeout = const Duration(seconds: 2),
    this.protocolProbeTimeout = const Duration(milliseconds: 800),
    this.commandRecoveryInterval = const Duration(milliseconds: 80),
  });

  final Duration responseTimeout;
  final Duration protocolProbeTimeout;
  final Duration commandRecoveryInterval;
  final FlutterClassicBluetooth _bluetooth = FlutterClassicBluetooth();
  LegacyOvParser _parser = LegacyOvParser();
  final StreamController<WatchSnapshot> _snapshotController =
      StreamController<WatchSnapshot>.broadcast();
  final StreamController<String> _logController =
      StreamController<String>.broadcast();
  final StreamController<WatchLinkState> _linkStateController =
      StreamController<WatchLinkState>.broadcast();

  BtcReconnectingConnection? _connection;
  StreamSubscription<String>? _lineSubscription;
  StreamSubscription<BtcReconnectState>? _stateSubscription;
  bool? _supportsVersionedData;
  Future<void> _transactionTail = Future<void>.value();
  int _session = 0;
  Completer<void>? _activeResponse;
  bool Function(String, WatchSnapshot?)? _responseMatches;

  @override
  Stream<WatchSnapshot> get snapshots => _snapshotController.stream;

  @override
  Stream<String> get logs => _logController.stream;

  @override
  Stream<WatchLinkState> get linkStates => _linkStateController.stream;

  @override
  bool get isConnected => _connection?.isConnected ?? false;

  @override
  Future<List<WatchDevice>> pairedDevices() async {
    await _ensureReady();
    final devices = await _bluetooth.getPairedDevices();
    return devices
        .map(
          (device) =>
              WatchDevice(name: device.displayName, address: device.address),
        )
        .toList(growable: false);
  }

  @override
  Future<void> connect(String address) async {
    await disconnect();
    await _ensureReady();
    _supportsVersionedData = null;
    _log('CONNECT $address');
    _linkStateController.add(WatchLinkState.connecting);
    final connection = _bluetooth.connectWithReconnect(
      address: address,
      uuid: BtcUuid.spp,
      policy: const BtcReconnectPolicy(
        maxAttempts: 5,
        initialBackoff: Duration(seconds: 1),
        maxBackoff: Duration(seconds: 8),
        connectTimeout: Duration(seconds: 12),
      ),
    );
    _connection = connection;
    _lineSubscription = connection.input.lines().listen(
      (line) {
        _log('RX $line');
        final isVersionedFrame = line.trimLeft().startsWith('OVD|');
        final snapshot = _parser.addLine(line);
        if (isVersionedFrame && snapshot != null) {
          _supportsVersionedData = true;
        }
        if (snapshot != null) _snapshotController.add(snapshot);
        final response = _activeResponse;
        if (response != null && !response.isCompleted) {
          try {
            if (_responseMatches?.call(line, snapshot) ?? false) {
              response.complete();
            }
          } on FormatException catch (error) {
            response.completeError(
              WatchTransportException('手表回传数据无效：${error.message}'),
            );
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _log('ERROR $error');
        _snapshotController.addError(error, stackTrace);
      },
      onDone: () => _log('DISCONNECTED'),
    );
    _stateSubscription = connection.state.listen(
      _onReconnectState,
      onError: (Object error, StackTrace stackTrace) {
        _log('ERROR $error');
        _invalidateSession();
        _linkStateController.add(WatchLinkState.failed);
      },
    );
    _onReconnectState(connection.currentState);
  }

  @override
  Future<void> requestSnapshot() {
    return _enqueue((session) async {
      _parser = LegacyOvParser();
      if (_supportsVersionedData == null) {
        try {
          await _sendAndWait(
            session,
            'OV+DATA',
            (line, snapshot) =>
                line.trimLeft().startsWith('OVD|') && snapshot != null,
            timeout: protocolProbeTimeout,
          );
          return;
        } on TimeoutException {
          _ensureSession(session);
          _supportsVersionedData = false;
          _log('INFO OV+DATA unsupported; falling back to OV+SEND');
        }
      }

      final versioned = _supportsVersionedData == true;
      try {
        await _sendAndWait(
          session,
          versioned ? 'OV+DATA' : 'OV+SEND',
          (line, snapshot) =>
              snapshot != null &&
              line.trimLeft().startsWith('OVD|') == versioned,
        );
      } on TimeoutException {
        _ensureSession(session);
        throw const WatchTransportException('读取手表数据超时，请确认手表蓝牙连接正常');
      }
    });
  }

  @override
  Future<void> syncClock(DateTime time) {
    final command =
        'OV+ST=${_four(time.year)}${_two(time.month)}'
        '${_two(time.day)}${_two(time.hour)}${_two(time.minute)}'
        '${_two(time.second)}';
    return _enqueue((session) async {
      String? rejection;
      try {
        await _sendAndWait(session, command, (line, snapshot) {
          if (line.trim() == 'TIMESETOK') return true;
          final match = RegExp(
            r'^OVERR\|1\|cmd=ST\|code=([A-Z_]+)$',
          ).firstMatch(line.trim());
          if (match == null) return false;
          rejection = switch (match[1]) {
            'SYNC_DISABLED' => '手表未开启“同步APP”，请在手表“设置 → 日期时间”中开启后重试',
            'INVALID_LENGTH' => '手表拒绝校时：命令长度不正确，请更新 App 和手表固件',
            'INVALID_TIME' => '手表拒绝校时：日期时间无效，请检查手机时间',
            'RTC_ERROR' => '手表时钟写入失败，请重试；若持续失败请检查手表固件',
            _ => '手表拒绝校时：${match[1]}',
          };
          return true;
        });
        if (rejection != null) throw WatchTransportException(rejection!);
      } on TimeoutException {
        _ensureSession(session);
        throw const WatchTransportException(
          '校时未收到手表确认，请先在手表“日期时间”中打开“同步APP”，再重试',
        );
      }
    });
  }

  @override
  Future<WatchCapabilities?> requestCapabilities() async {
    WatchCapabilities? result;
    try {
      await _enqueue(
        (session) => _sendAndWait(session, 'OV+CAP', (line, snapshot) {
          if (!line.trim().startsWith('OVCAP|')) return false;
          result = WatchCapabilities.parse(line);
          return true;
        }, timeout: protocolProbeTimeout),
      );
    } on TimeoutException {
      return null;
    }
    return result;
  }

  @override
  Future<WatchStopwatchSnapshot> requestStopwatch() async {
    late WatchStopwatchSnapshot result;
    await _enqueue(
      (session) => _sendAndWait(session, 'OV+SW', (line, snapshot) {
        if (!line.trim().startsWith('OVSW|')) return false;
        result = WatchStopwatchSnapshot.parse(line);
        return true;
      }),
    );
    return result;
  }

  @override
  Future<WatchStopwatchLog> requestStopwatchLog({int afterSid = 0}) async {
    RangeError.checkValueInInterval(afterSid, 0, 0xffffffff, 'afterSid');
    late WatchStopwatchLog result;
    await _enqueue(
      (session) =>
          _sendAndWait(session, 'OV+SWLOG=$afterSid', (line, snapshot) {
            if (!line.trim().startsWith('OVSL|')) return false;
            result = WatchStopwatchLog.parse(line);
            return true;
          }),
    );
    return result;
  }

  Future<void> _enqueue(Future<void> Function(int session) action) {
    final session = _session;
    final operation = _transactionTail.then((_) async {
      _ensureSession(session);
      await action(session);
    });
    // A failed transaction must not poison the remaining queue.
    _transactionTail = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<void> _sendAndWait(
    int session,
    String command,
    bool Function(String, WatchSnapshot?) matches, {
    Duration? timeout,
  }) async {
    _ensureSession(session);
    final response = Completer<void>();
    _activeResponse = response;
    _responseMatches = matches;
    _log('TX $command');
    try {
      // Register the waiter before sending; firmware matches exact bytes, without
      // CR/LF. Keep the transaction occupied until the complete reply arrives.
      await Future.wait<void>([
        _connection!.sendString(command),
        response.future,
      ], eagerError: true).timeout(timeout ?? responseTimeout);
    } finally {
      if (identical(_activeResponse, response)) {
        _activeResponse = null;
        _responseMatches = null;
      }
      // The firmware clears its shared DMA buffer after printing the response.
      await Future<void>.delayed(commandRecoveryInterval);
    }
    _ensureSession(session);
  }

  void _ensureSession(int session) {
    if (session != _session || !isConnected) {
      throw const WatchTransportException('蓝牙连接已中断，请重新连接后重试');
    }
  }

  void _invalidateSession() {
    _session++;
    _supportsVersionedData = null;
    _parser = LegacyOvParser();
    final response = _activeResponse;
    _activeResponse = null;
    _responseMatches = null;
    if (response != null && !response.isCompleted) {
      response.completeError(const WatchTransportException('蓝牙连接已中断，请重新连接后重试'));
    }
    _transactionTail = Future<void>.value();
  }

  String _two(int value) => value.toString().padLeft(2, '0');
  String _four(int value) => value.toString().padLeft(4, '0');

  void _log(String line) => _logController.add(line);

  @override
  Future<void> disconnect() async {
    _invalidateSession();
    await _lineSubscription?.cancel();
    _lineSubscription = null;
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    final connection = _connection;
    _connection = null;
    if (connection != null) {
      await connection.close();
    }
    _linkStateController.add(WatchLinkState.disconnected);
  }

  Future<void> _ensureReady() async {
    if (!await _bluetooth.isSupported()) {
      throw const WatchTransportException('此手机不支持经典蓝牙 SPP');
    }
    if (!await _bluetooth.isEnabled()) {
      throw const WatchTransportException('请先打开手机蓝牙');
    }

    // The Android connector cancels discovery before opening its RFCOMM socket.
    // Android 12+ requires scan permission for that call, even for paired devices.
    const permissions = {BtcPermission.connect, BtcPermission.scan};
    var status = await _bluetooth.checkPermissions(permissions: permissions);
    if (status == BtcPermissionStatus.denied) {
      status = await _bluetooth.requestPermissions(permissions: permissions);
    }
    switch (status) {
      case BtcPermissionStatus.granted:
      case BtcPermissionStatus.notRequired:
        return;
      case BtcPermissionStatus.denied:
        throw const WatchTransportException('需要“附近设备”权限才能连接手表');
      case BtcPermissionStatus.permanentlyDenied:
        throw const WatchTransportException(
          '蓝牙权限已被永久拒绝，请在应用设置中允许“附近设备”',
          canOpenSettings: true,
        );
    }
  }

  void _onReconnectState(BtcReconnectState state) {
    _log('STATE ${state.name}');
    switch (state) {
      case BtcReconnectState.connecting:
        _invalidateSession();
        _linkStateController.add(WatchLinkState.connecting);
      case BtcReconnectState.connected:
        _invalidateSession();
        unawaited(_handshake());
      case BtcReconnectState.reconnecting:
        _invalidateSession();
        _linkStateController.add(WatchLinkState.reconnecting);
      case BtcReconnectState.closed:
        _invalidateSession();
        _linkStateController.add(WatchLinkState.disconnected);
      case BtcReconnectState.failed:
        _invalidateSession();
        final error = _connection?.lastError;
        if (error != null) _log('ERROR $error');
        _linkStateController.add(WatchLinkState.failed);
    }
  }

  Future<void> _handshake() async {
    final session = _session;
    try {
      await _enqueue(
        (session) => _sendAndWait(
          session,
          'OV',
          (line, snapshot) => line.trim() == 'OK',
        ),
      );
      // The controller starts polling on connected; wait for the acknowledgement
      // so its first request cannot merge with OV in the firmware DMA buffer.
      if (session == _session && isConnected) {
        _linkStateController.add(WatchLinkState.connected);
      }
    } catch (error) {
      if (session != _session || !isConnected) return;
      _log('ERROR handshake: $error');
      _linkStateController.add(WatchLinkState.failed);
    }
  }

  @override
  Future<void> openAppSettings() async {
    await _bluetooth.openAppSettings();
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _snapshotController.close();
    await _logController.close();
    await _linkStateController.close();
  }
}
