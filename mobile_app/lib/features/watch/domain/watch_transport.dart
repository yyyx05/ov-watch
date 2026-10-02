import 'watch_snapshot.dart';

enum WatchLinkState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

class WatchDevice {
  const WatchDevice({required this.name, required this.address});

  final String name;
  final String address;
}

class WatchTransportException implements Exception {
  const WatchTransportException(this.message, {this.canOpenSettings = false});

  final String message;
  final bool canOpenSettings;

  @override
  String toString() => message;
}

abstract interface class WatchTransport {
  Stream<WatchSnapshot> get snapshots;
  Stream<String> get logs;
  Stream<WatchLinkState> get linkStates;
  bool get isConnected;

  Future<List<WatchDevice>> pairedDevices();
  Future<void> connect(String address);
  Future<void> disconnect();
  Future<void> requestSnapshot();
  Future<void> syncClock(DateTime time);
  Future<void> openAppSettings();
  Future<void> dispose();
}
