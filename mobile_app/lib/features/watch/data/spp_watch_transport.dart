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

  BtcConnection? _connection;
  StreamSubscription<String>? _lineSubscription;

  @override
  Stream<WatchSnapshot> get snapshots => _snapshotController.stream;

  @override
  Stream<String> get logs => _logController.stream;

  @override
  bool get isConnected => _connection?.isConnected ?? false;

  @override
  Future<List<WatchDevice>> pairedDevices() async {
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
    _log('CONNECT $address');
    final connection = await _bluetooth.connect(
      address: address,
      uuid: BtcUuid.spp,
      timeout: const Duration(seconds: 12),
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
    await _writeLine('OV');
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
    await connection.output.writeLine(command);
  }

  String _two(int value) => value.toString().padLeft(2, '0');
  String _four(int value) => value.toString().padLeft(4, '0');

  void _log(String line) => _logController.add(line);

  @override
  Future<void> disconnect() async {
    await _lineSubscription?.cancel();
    _lineSubscription = null;
    final connection = _connection;
    _connection = null;
    if (connection != null) {
      await connection.close();
      connection.dispose();
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _snapshotController.close();
    await _logController.close();
  }
}
