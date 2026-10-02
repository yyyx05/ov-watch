import 'dart:async';

import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

import '../domain/watch_snapshot.dart';
import '../domain/watch_transport.dart';
import 'legacy_ov_parser.dart';

class SppWatchTransport implements WatchTransport {
  final FlutterClassicBluetooth _bluetooth = FlutterClassicBluetooth();
  final LegacyOvParser _parser = LegacyOvParser();
  final StreamController<WatchSnapshot> _snapshotController =
      StreamController<WatchSnapshot>.broadcast();
  final StreamController<String> _logController =
      StreamController<String>.broadcast();
  final StreamController<WatchLinkState> _linkStateController =
      StreamController<WatchLinkState>.broadcast();

  BtcReconnectingConnection? _connection;
  StreamSubscription<String>? _lineSubscription;
  StreamSubscription<BtcReconnectState>? _stateSubscription;

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
        final snapshot = _parser.addLine(line);
        if (snapshot != null) _snapshotController.add(snapshot);
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
        _linkStateController.add(WatchLinkState.failed);
      },
    );
    _onReconnectState(connection.currentState);
  }

  @override
  Future<void> requestSnapshot() => _writeLine('OV+SEND');

  @override
  Future<void> syncClock(DateTime time) {
    final command =
        'OV+ST=${_four(time.year)}${_two(time.month)}'
        '${_two(time.day)}${_two(time.hour)}${_two(time.minute)}'
        '${_two(time.second)}';
    return _writeLine(command);
  }

  Future<void> _writeLine(String command) async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) {
      throw StateError('手表尚未连接');
    }
    _log('TX $command');
    await connection.sendLine(command);
  }

  String _two(int value) => value.toString().padLeft(2, '0');
  String _four(int value) => value.toString().padLeft(4, '0');

  void _log(String line) => _logController.add(line);

  @override
  Future<void> disconnect() async {
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

    const permissions = {BtcPermission.connect};
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
        _linkStateController.add(WatchLinkState.connecting);
      case BtcReconnectState.connected:
        _linkStateController.add(WatchLinkState.connected);
        unawaited(
          _writeLine('OV').catchError((Object error) => _log('ERROR $error')),
        );
      case BtcReconnectState.reconnecting:
        _linkStateController.add(WatchLinkState.reconnecting);
      case BtcReconnectState.closed:
        _linkStateController.add(WatchLinkState.disconnected);
      case BtcReconnectState.failed:
        final error = _connection?.lastError;
        if (error != null) _log('ERROR $error');
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
