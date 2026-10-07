import 'package:flutter/services.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ov_watch_app/features/watch/data/spp_watch_transport.dart';
import 'package:ov_watch_app/features/watch/domain/watch_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _BluetoothHarness bluetooth;
  late SppWatchTransport transport;
  late List<WatchLinkState> states;

  setUp(() {
    bluetooth = _BluetoothHarness();
    transport = SppWatchTransport(
      responseTimeout: const Duration(milliseconds: 250),
      protocolProbeTimeout: const Duration(milliseconds: 100),
      commandRecoveryInterval: const Duration(milliseconds: 30),
    );
    states = [];
    transport.linkStates.listen(states.add);
  });

  tearDown(() async {
    await transport.dispose();
    await _settle(const Duration(milliseconds: 40));
    bluetooth.dispose();
  });

  Future<void> connect() async {
    final previousWrites = bluetooth.writes.length;
    await transport.connect(_BluetoothHarness.address);
    await _until(() => bluetooth.writes.length > previousWrites);
    expect(bluetooth.writes.last, 'OV');
    bluetooth.receive('RecStr:OV\r\nOK\r\n');
    await _until(() => states.last == WatchLinkState.connected);
  }

  test(
    'waits for fragmented OK and requests both Android permissions',
    () async {
      bluetooth.permissionsGranted = false;
      await transport.connect(_BluetoothHarness.address);
      await _until(() => bluetooth.writes.isNotEmpty);
      expect(
        bluetooth.checkedPermissions,
        unorderedEquals(['connect', 'scan']),
      );
      expect(
        bluetooth.requestedPermissions,
        unorderedEquals(['connect', 'scan']),
      );
      expect(bluetooth.writes, ['OV']);
      expect(states, isNot(contains(WatchLinkState.connected)));

      bluetooth.receive('RecStr:OV\r\nO');
      await _settle();
      expect(states, isNot(contains(WatchLinkState.connected)));
      bluetooth.receive('K\r\n');
      await _until(() => states.last == WatchLinkState.connected);

      final sample = transport.requestSnapshot();
      await _until(() => bluetooth.writes.length == 2);
      expect(bluetooth.writes.last, 'OV+DATA');
      bluetooth.receive(_versionedFrame);
      await sample;
    },
  );

  test('reports a bounded handshake failure when OK never arrives', () async {
    await transport.connect(_BluetoothHarness.address);
    await _until(() => bluetooth.writes.isNotEmpty);
    bluetooth.receive('RecStr:OV\r\n');
    await _until(() => states.last == WatchLinkState.failed);
    expect(states, isNot(contains(WatchLinkState.connected)));
    expect(bluetooth.writes, ['OV']);
  });

  test('ignores an outstanding handshake after manual disconnect', () async {
    await transport.connect(_BluetoothHarness.address);
    await _until(() => bluetooth.writes.isNotEmpty);
    await transport.disconnect();
    await _settle(const Duration(milliseconds: 320));
    expect(states.last, WatchLinkState.disconnected);
    expect(states, isNot(contains(WatchLinkState.failed)));
    expect(states, isNot(contains(WatchLinkState.connected)));
  });

  test(
    'holds queued clock sync until the complete legacy sample arrives',
    () async {
      await connect();
      var sampleCompleted = false;
      final sample = transport.requestSnapshot().then(
        (_) => sampleCompleted = true,
      );
      var clockCompleted = false;
      final clock = transport
          .syncClock(DateTime(2026, 10, 7, 16, 30, 45))
          .then((_) => clockCompleted = true);

      await _until(() => bluetooth.writes.length == 3);
      expect(bluetooth.writes, ['OV', 'OV+DATA', 'OV+SEND']);
      expect(sampleCompleted, isFalse);
      bluetooth.receive(_legacyFramePrefix);
      await _settle();
      expect(sampleCompleted, isFalse);
      expect(bluetooth.writes.length, 3);

      final repliedAt = DateTime.now();
      bluetooth.receive('Step today:42\r\n');
      await sample;
      await _until(() => bluetooth.writes.length == 4);
      expect(bluetooth.writes.last, 'OV+ST=20261007163045');
      expect(bluetooth.writes.last.length, 20);
      expect(
        bluetooth.writeTimes.last.difference(repliedAt),
        greaterThanOrEqualTo(transport.commandRecoveryInterval),
      );
      expect(clockCompleted, isFalse);
      bluetooth.receive('RecStr:OV+ST=20261007163045\r\n');
      await _settle();
      expect(clockCompleted, isFalse);
      bluetooth.receive('TIMESETOK\r\n');
      await clock;
      expect(clockCompleted, isTrue);
    },
  );

  test(
    'clock timeout explains watch setting and releases the next sample',
    () async {
      await connect();
      final clock = transport.syncClock(DateTime(2026, 10, 7, 16, 30, 45));
      final failure = expectLater(
        clock,
        throwsA(
          isA<WatchTransportException>().having(
            (error) => error.message,
            'message',
            contains('同步APP'),
          ),
        ),
      );
      final sample = transport.requestSnapshot();
      await _until(() => bluetooth.writes.length == 2);
      expect(bluetooth.writes.last, startsWith('OV+ST='));
      await failure;
      await _until(() => bluetooth.writes.length == 3);
      expect(bluetooth.writes.last, 'OV+DATA');
      bluetooth.receive(_versionedFrame);
      await sample;
    },
  );

  test('sample timeout releases a queued clock command', () async {
    await connect();
    final sample = transport.requestSnapshot();
    final failure = expectLater(
      sample,
      throwsA(
        isA<WatchTransportException>().having(
          (error) => error.message,
          'message',
          contains('读取手表数据超时'),
        ),
      ),
    );
    final clock = transport.syncClock(DateTime(2026, 10, 7));
    await failure;
    await _until(() => bluetooth.writes.length == 4);
    expect(bluetooth.writes, [
      'OV',
      'OV+DATA',
      'OV+SEND',
      'OV+ST=20261007000000',
    ]);
    bluetooth.receive('TIMESETOK\r\n');
    await clock;
  });

  test(
    'cancels active and queued commands before a manual new connection',
    () async {
      await connect();
      final sample = transport.requestSnapshot();
      final sampleFailure = expectLater(
        sample,
        throwsA(isA<WatchTransportException>()),
      );
      final clock = transport.syncClock(DateTime(2026, 10, 7));
      final clockFailure = expectLater(
        clock,
        throwsA(isA<WatchTransportException>()),
      );
      await _until(() => bluetooth.writes.length == 2);
      await transport.disconnect();
      await connect();
      await Future.wait([sampleFailure, clockFailure]);
      expect(bluetooth.writes, ['OV', 'OV+DATA', 'OV']);

      final freshSample = transport.requestSnapshot();
      await _until(() => bluetooth.writes.length == 4);
      bluetooth.receive(_versionedFrame);
      await freshSample;
      expect(bluetooth.writes, ['OV', 'OV+DATA', 'OV', 'OV+DATA']);
    },
  );

  test('companion commands share the sample and clock transaction queue', () async {
    await connect();
    final sample = transport.requestSnapshot();
    final capabilities = transport.requestCapabilities();
    final stopwatch = transport.requestStopwatch();
    final history = transport.requestStopwatchLog(afterSid: 4294967294);
    await _until(() => bluetooth.writes.length == 2);
    expect(bluetooth.writes.last, 'OV+DATA');
    bluetooth.receive(_versionedFrame);
    await sample;
    await _until(() => bluetooth.writes.length == 3);
    expect(bluetooth.writes.last, 'OV+CAP');
    bluetooth.receive(
      'OVCAP|1|data=1|clock=1|clock_sync=0|sw=1|swlog=1|swlog_cap=8|persist=0\r\n',
    );
    expect((await capabilities)!.stopwatch, isTrue);
    await _until(() => bluetooth.writes.length == 4);
    expect(bluetooth.writes.last, 'OV+SW');
    bluetooth.receive(
      'OVSW|1|boot=9|sid=4294967295|state=pause|elapsed_ms=3210\r\n',
    );
    expect((await stopwatch).elapsedMs, 3210);
    await _until(() => bluetooth.writes.length == 5);
    expect(bluetooth.writes.last, 'OV+SWLOG=4294967294');
    bluetooth.receive(
      'OVSL|1|boot=9|sid=4294967295|end=20261007T163045|dur_ms=3210|more=0\r\n',
    );
    expect((await history).sid, 4294967295);
    expect(
      bluetooth.writes.every((command) => !command.contains('\n')),
      isTrue,
    );
  });

  test(
    'legacy capability timeout returns unsupported and malformed data fails safely',
    () async {
      await connect();
      expect(await transport.requestCapabilities(), isNull);
      final pending = transport.requestStopwatch();
      final failed = expectLater(
        pending,
        throwsA(isA<WatchTransportException>()),
      );
      await _until(() => bluetooth.writes.last == 'OV+SW');
      bluetooth.receive('OVSW|1|boot=9|sid=1|state=run|elapsed_ms=-1\r\n');
      await failed;
      final next = transport.requestStopwatch();
      await _until(() => bluetooth.writes.length == 4);
      bluetooth.receive('OVSW|1|boot=9|sid=0|state=idle|elapsed_ms=0\r\n');
      expect((await next).elapsedMs, 0);
    },
  );

  test(
    'clock firmware errors give actionable Chinese failure, not success',
    () async {
      await connect();
      for (final entry in {
        'SYNC_DISABLED': '同步APP',
        'INVALID_LENGTH': '长度',
        'INVALID_TIME': '日期时间无效',
        'RTC_ERROR': '写入失败',
      }.entries) {
        final count = bluetooth.writes.length;
        final pending = transport.syncClock(DateTime(2026, 10, 7));
        final failed = expectLater(
          pending,
          throwsA(
            isA<WatchTransportException>().having(
              (error) => error.message,
              'message',
              contains(entry.value),
            ),
          ),
        );
        await _until(() => bluetooth.writes.length > count);
        bluetooth.receive('OVERR|1|cmd=ST|code=${entry.key}\r\n');
        await failed;
      }
    },
  );

  test(
    'cancels the previous queue when the socket automatically reconnects',
    () async {
      await connect();
      final sample = transport.requestSnapshot();
      final sampleFailure = expectLater(
        sample,
        throwsA(isA<WatchTransportException>()),
      );
      final clock = transport.syncClock(DateTime(2026, 10, 7));
      final clockFailure = expectLater(
        clock,
        throwsA(isA<WatchTransportException>()),
      );
      await _until(() => bluetooth.writes.length == 2);
      bluetooth.dropConnection();
      await Future.wait([sampleFailure, clockFailure]);
      await _until(() => bluetooth.writes.length == 3);
      expect(bluetooth.writes, ['OV', 'OV+DATA', 'OV']);
      bluetooth.receive('OK\r\n');
      await _until(() => states.last == WatchLinkState.connected);
      expect(bluetooth.writes, ['OV', 'OV+DATA', 'OV']);
    },
  );
}

const _versionedFrame =
    'OVD|1|ts=20261007T163045|temp=26|humi=61|hr=74|spo2=na|steps=42\r\n';
const _legacyFramePrefix =
    'RecStr:OV+SEND\r\ndata:10-07\r\ntime:16:30:45\r\nhumidity:61%\r\ntemperature:26\r\nHeart Rate:74%\r\nSPO2:0%\r\n';

Future<void> _settle([Duration delay = const Duration(milliseconds: 10)]) =>
    Future<void>.delayed(delay);

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for Bluetooth event');
    }
    await _settle();
  }
}

class _BluetoothHarness {
  static const address = 'AA:BB:CC:DD:EE:FF';
  static const _method = MethodChannel('flutter_classic_bluetooth/methods');
  final writes = <String>[];
  final writeTimes = <DateTime>[];
  final _channels = <EventChannel>[];
  bool permissionsGranted = true;
  List<Object?> checkedPermissions = [];
  List<Object?> requestedPermissions = [];
  final _messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final _previousPlatform = FlutterClassicBluetoothPlatform.instance;
  MockStreamHandlerEventSink? _dataSink;
  MockStreamHandlerEventSink? _stateSink;
  int _connectionId = 0;

  _BluetoothHarness() {
    FlutterClassicBluetoothPlatform.instance =
        MethodChannelFlutterClassicBluetooth();
    _messenger.setMockMethodCallHandler(_method, (call) async {
      switch (call.method) {
        case 'isSupported':
        case 'isEnabled':
          return true;
        case 'checkPermissions':
          checkedPermissions = List<Object?>.from(
            call.arguments['permissions'],
          );
          return permissionsGranted ? 'granted' : 'denied';
        case 'requestPermissions':
          requestedPermissions = List<Object?>.from(
            call.arguments['permissions'],
          );
          permissionsGranted = true;
          return 'granted';
        case 'connect':
          _connectionId++;
          final data = EventChannel(
            'flutter_classic_bluetooth/connection/$_connectionId',
          );
          final state = EventChannel(
            'flutter_classic_bluetooth/connection_state/$_connectionId',
          );
          _channels.addAll([data, state]);
          _messenger.setMockStreamHandler(
            data,
            MockStreamHandler.inline(
              onListen: (args, sink) {
                _dataSink = sink;
              },
            ),
          );
          _messenger.setMockStreamHandler(
            state,
            MockStreamHandler.inline(
              onListen: (args, sink) {
                _stateSink = sink;
              },
            ),
          );
          return {'id': _connectionId};
        case 'write':
          writes.add(String.fromCharCodes(call.arguments['data'] as Uint8List));
          writeTimes.add(DateTime.now());
          return null;
        case 'disconnect':
          return null;
        default:
          throw StateError('Unexpected Bluetooth call: ${call.method}');
      }
    });
  }

  void receive(String value) =>
      _dataSink!.success(Uint8List.fromList(value.codeUnits));
  void dropConnection() => _stateSink!.success('disconnected');

  void dispose() {
    _messenger.setMockMethodCallHandler(_method, null);
    for (final channel in _channels) {
      _messenger.setMockStreamHandler(channel, null);
    }
    FlutterClassicBluetoothPlatform.instance = _previousPlatform;
  }
}
