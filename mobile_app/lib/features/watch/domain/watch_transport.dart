import 'watch_snapshot.dart';

class WatchDevice {
  const WatchDevice({required this.name, required this.address});

  final String name;
  final String address;
}

abstract interface class WatchTransport {
  Stream<WatchSnapshot> get snapshots;
  Stream<String> get logs;
  bool get isConnected;

  Future<List<WatchDevice>> pairedDevices();
  Future<void> connect(String address);
  Future<void> disconnect();
  Future<void> requestSnapshot();
  Future<void> syncClock(DateTime time);
  Future<void> dispose();
}
