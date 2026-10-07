import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ov_watch_app/features/history/data/health_history_repository.dart';
import 'package:ov_watch_app/features/stopwatch/application/watch_stopwatch_controller.dart';
import 'package:ov_watch_app/features/stopwatch/data/stopwatch_repository.dart';
import 'package:ov_watch_app/features/stopwatch/domain/watch_companion.dart';
import 'package:ov_watch_app/features/stopwatch/presentation/stopwatch_page.dart';
import 'package:ov_watch_app/features/watch/application/watch_controller.dart';
import 'package:ov_watch_app/features/watch/domain/watch_snapshot.dart';
import 'package:ov_watch_app/features/watch/domain/watch_transport.dart';
import 'package:sqflite/sqflite.dart';

const _capLine =
    'OVCAP|1|data=1|clock=1|clock_sync=0|sw=1|swlog=1|swlog_cap=8|persist=0';
const _logLine = 'OVSL|1|boot=41|sid=1|end=20261007T163045|dur_ms=65000|more=0';

void main() {
  test('strict parser accepts capability, paused stopwatch and uint32 ids', () {
    final cap = WatchCapabilities.parse(_capLine);
    expect(cap.stopwatch, isTrue);
    expect(cap.clockSyncEnabled, isFalse);
    expect(cap.persistent, isFalse);
    final current = WatchStopwatchSnapshot.parse(
      'OVSW|1|boot=4294967295|sid=4294967295|state=pause|elapsed_ms=4294967295',
    );
    expect(current.state, WatchStopwatchState.pause);
    expect(current.sid, 0xffffffff);
    expect(
      WatchStopwatchLog.parse(_logLine).endedAt,
      DateTime.utc(2026, 10, 7, 16, 30, 45),
    );
    expect(WatchStopwatchLog.parse('OVSL|1|boot=41|none=1').isEmpty, isTrue);
  });

  test(
    'RTC identity and stored calendar fields do not depend on phone timezone',
    () async {
      final parsed = WatchStopwatchLog.parse(_logLine);
      expect(parsed.endedAt!.isUtc, isTrue);
      final localContainer = _record();
      final utcContainer = StopwatchRecord(
        deviceAddress: localContainer.deviceAddress,
        deviceName: localContainer.deviceName,
        boot: parsed.boot,
        sid: parsed.sid!,
        endedAt: parsed.endedAt!,
        durationMs: parsed.durationMs!,
        importedAt: localContainer.importedAt,
      );
      // Same RTC fields from local and UTC constructors must encode identically,
      // even on this +08:00 machine where their actual epochs differ by 8 hours.
      expect(localContainer.key, utcContainer.key);
      expect(
        localContainer.toMap()['ended_at'],
        utcContainer.toMap()['ended_at'],
      );
      final restored = StopwatchRecord.fromMap(utcContainer.toMap());
      expect(restored.endedAt, DateTime.utc(2026, 10, 7, 16, 30, 45));
      expect(restored.key, utcContainer.key);
      expect(restored.toMap()['ended_at'], utcContainer.toMap()['ended_at']);

      final repository = SqliteStopwatchRepository(database: _MemoryDatabase());
      await repository.upsert(localContainer);
      await repository.annotate(localContainer.key, StopwatchTag.study, '保留备注');
      await repository.upsert(restored);
      final saved = (await repository.recent()).single;
      expect(saved.note, '保留备注');
      expect(saved.endedAt.hour, 16);
      expect(saved.key, restored.key);
      await repository.dispose();
    },
  );

  test('parser rejects invalid, duplicate, missing and overflowing fields', () {
    for (final value in [
      'OVSW|1|boot=1|sid=1|state=running|elapsed_ms=1',
      'OVSW|1|boot=1|sid=1|state=run|elapsed_ms=-1',
      'OVSW|1|boot=1|sid=1|state=run|elapsed_ms=4294967296',
      'OVSW|1|boot=1|sid=0|state=run|elapsed_ms=0',
      'OVSW|1|boot=1|sid=1|state=run|elapsed_ms=1|sid=2',
      'OVSW|2|boot=1|sid=1|state=run|elapsed_ms=1',
      'OVSW|1|boot=1|state=run|elapsed_ms=1',
    ]) {
      expect(() => WatchStopwatchSnapshot.parse(value), throwsFormatException);
    }
    for (final value in [
      _logLine.replaceFirst('20261007', '20260230'),
      _logLine.replaceFirst('T163045', 'T246000'),
      _logLine.replaceFirst('more=0', 'more=2'),
      'OVSL|1|boot=1|none=1|sid=1',
    ]) {
      expect(() => WatchStopwatchLog.parse(value), throwsFormatException);
    }
    expect(
      () => WatchCapabilities.parse(_capLine.replaceFirst('sw=1', 'sw=x')),
      throwsFormatException,
    );
  });

  test(
    'SQLite repository reimport preserves notes, immutable time and collision variants',
    () async {
      final database = _MemoryDatabase();
      final repository = SqliteStopwatchRepository(database: database);
      final record = _record();
      await repository.upsert(record);
      await repository.annotate(record.key, StopwatchTag.study, '  第三章  ');
      await repository.upsert(record);
      expect(database.lastConflict, ConflictAlgorithm.ignore);
      final saved = (await repository.recent()).single;
      expect(saved.tag, StopwatchTag.study);
      expect(saved.note, '第三章');
      expect(saved.durationMs, record.durationMs);
      expect(database.lastUpdate!.keys, unorderedEquals(['tag', 'note']));
      await repository.upsert(_record(address: 'other'));
      await repository.upsert(_record(boot: 42));
      await repository.upsert(_record(durationMs: 66000));
      expect((await repository.recent()).length, 4);
      await expectLater(
        repository.annotate(record.key, StopwatchTag.other, 'a' * 241),
        throwsFormatException,
      );
    },
  );

  test(
    'old firmware probed once per connection and never fabricates stopwatch',
    () async {
      final fixture = await _Fixture.create();
      fixture.transport.cap = null;
      await fixture.connect();
      fixture.controller.setVisible(true);
      fixture.transport.emitLog('anything');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(fixture.transport.capRequests, 1);
      expect(fixture.transport.stateRequests, 0);
      expect(fixture.controller.support, StopwatchSupport.unsupported);
      expect(fixture.controller.snapshot, isNull);
      await fixture.controller.refreshCapabilities();
      expect(fixture.transport.capRequests, 2);
      fixture.dispose();
    },
  );

  test(
    'only visible foreground polls, history deduplicates and pause is not archived',
    () async {
      final fixture = await _Fixture.create();
      fixture.transport.entries = [WatchStopwatchLog.parse(_logLine)];
      await fixture.connect();
      expect(fixture.controller.records.length, 1);
      expect(fixture.transport.stateRequests, 0);
      await fixture.controller.syncHistory();
      expect(fixture.controller.records.length, 1);
      fixture.controller.setVisible(true);
      await Future<void>.delayed(const Duration(milliseconds: 85));
      expect(fixture.transport.stateRequests, greaterThanOrEqualTo(2));
      final before = fixture.transport.logRequests;
      fixture.transport.current = const WatchStopwatchSnapshot(
        boot: 41,
        sid: 2,
        state: WatchStopwatchState.pause,
        elapsedMs: 500,
      );
      await Future<void>.delayed(const Duration(milliseconds: 45));
      expect(fixture.controller.snapshot!.state, WatchStopwatchState.pause);
      expect(fixture.transport.logRequests, before);
      fixture.controller.setAppActive(false);
      final count = fixture.transport.stateRequests;
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(fixture.transport.stateRequests, count);
      fixture.controller.setAppActive(true);
      await Future<void>.delayed(const Duration(milliseconds: 45));
      expect(fixture.transport.stateRequests, greaterThan(count));
      fixture.controller.setVisible(false);
      final hidden = fixture.transport.stateRequests;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(fixture.transport.stateRequests, hidden);
      fixture.dispose();
    },
  );

  test(
    'new device ignores old pending capability and history responses',
    () async {
      final fixture = await _Fixture.create();
      final pending = Completer<WatchCapabilities?>();
      fixture.transport.pendingCap = pending;
      await fixture.connect();
      expect(fixture.controller.support, StopwatchSupport.checking);
      fixture.transport.pendingCap = null;
      fixture.transport.cap = null;
      await fixture.connect(address: '11:22');
      expect(fixture.controller.support, StopwatchSupport.unsupported);
      pending.complete(WatchCapabilities.parse(_capLine));
      await _flush();
      expect(fixture.controller.support, StopwatchSupport.unsupported);
      expect(fixture.controller.capabilities, isNull);
      expect(fixture.transport.logRequests, 0);
      fixture.dispose();
    },
  );

  test(
    'disconnect during log sync cannot store a response for the next device',
    () async {
      final fixture = await _Fixture.create();
      final pending = Completer<WatchStopwatchLog>();
      fixture.transport.pendingLog = pending;
      await fixture.connect();
      await fixture.watch.disconnect();
      await _flush();
      pending.complete(WatchStopwatchLog.parse(_logLine));
      await _flush();
      expect(fixture.controller.records, isEmpty);
      expect(fixture.database.rows, isEmpty);
      expect(fixture.controller.support, StopwatchSupport.disconnected);
      fixture.dispose();
    },
  );

  testWidgets(
    'offline UI shows saved duration and editable tag/note without fake timer',
    (tester) async {
      final fixture = await _Fixture.create();
      await fixture.repository.upsert(_record());
      await fixture.controller.refreshLocalHistory();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StopwatchPage(controller: fixture.controller)),
        ),
      );
      expect(find.text('--:--:--'), findsOneWidget);
      expect(find.text('手表未连接'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('00:01:05'), 150);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('00:01:05'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('00:01:05'));
      await tester.pumpAndSettle();
      expect(find.textContaining('不改变手表原始计时时长'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '学习').last);
      await tester.enterText(find.byType(TextField), '复习');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(fixture.controller.records.single.note, '复习');
      expect(fixture.controller.records.single.durationMs, 65000);
      await tester.pumpWidget(const SizedBox());
      fixture.dispose();
    },
  );

  testWidgets('history renders twenty at a time and filter resets pagination', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    for (var index = 0; index < 45; index++) {
      await fixture.repository.upsert(
        _record(address: 'watch-$index').annotate(StopwatchTag.study, ''),
      );
    }
    await fixture.controller.refreshLocalHistory();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StopwatchHistoryPanel(controller: fixture.controller),
          ),
        ),
      ),
    );
    expect(find.byType(ListTile), findsNWidgets(20));
    expect(find.textContaining('45 段记录'), findsOneWidget);
    final more = find.textContaining('查看更多');
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(40));
    fixture.controller.setTagFilter(StopwatchTag.study);
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(20));
    await tester.pumpWidget(const SizedBox());
    fixture.dispose();
  });
}

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 10));

StopwatchRecord _record({
  String address = 'AA:BB',
  int boot = 41,
  int durationMs = 65000,
}) => StopwatchRecord(
  deviceAddress: address,
  deviceName: 'OV-Watch',
  boot: boot,
  sid: 1,
  endedAt: DateTime(2026, 10, 7, 16, 30, 45),
  durationMs: durationMs,
  importedAt: DateTime(2026, 10, 7, 16, 31),
);

class _Fixture {
  _Fixture(
    this.transport,
    this.watch,
    this.repository,
    this.controller,
    this.database,
  );
  final _Transport transport;
  final WatchController watch;
  final SqliteStopwatchRepository repository;
  final WatchStopwatchController controller;
  final _MemoryDatabase database;
  static Future<_Fixture> create() async {
    final transport = _Transport();
    final watch = WatchController(
      transport: transport,
      historyRepository: _Health(),
    );
    watch.setAutoRefresh(false);
    await watch.initialize();
    final database = _MemoryDatabase();
    final repository = SqliteStopwatchRepository(database: database);
    final controller = WatchStopwatchController(
      watch: watch,
      transport: transport,
      repository: repository,
      pollInterval: const Duration(milliseconds: 30),
    );
    await controller.initialize();
    return _Fixture(transport, watch, repository, controller, database);
  }

  Future<void> connect({String address = 'AA:BB'}) async {
    await watch.connect(WatchDevice(name: 'OV-Watch', address: address));
    transport.links.add(WatchLinkState.connected);
    await _flush();
  }

  void dispose() {
    controller.dispose();
    watch.dispose();
  }
}

class _Transport implements WatchTransport, WatchCompanionTransport {
  final links = StreamController<WatchLinkState>.broadcast();
  final logStream = StreamController<String>.broadcast();
  final samples = StreamController<WatchSnapshot>.broadcast();
  WatchCapabilities? cap = WatchCapabilities.parse(_capLine);
  Completer<WatchCapabilities?>? pendingCap;
  Completer<WatchStopwatchLog>? pendingLog;
  List<WatchStopwatchLog> entries = [];
  WatchStopwatchSnapshot current = const WatchStopwatchSnapshot(
    boot: 41,
    sid: 2,
    state: WatchStopwatchState.run,
    elapsedMs: 100,
  );
  int capRequests = 0, stateRequests = 0, logRequests = 0;
  @override
  Future<WatchCapabilities?> requestCapabilities() async {
    capRequests++;
    return pendingCap == null ? cap : await pendingCap!.future;
  }

  @override
  Future<WatchStopwatchSnapshot> requestStopwatch() async {
    stateRequests++;
    return current;
  }

  @override
  Future<WatchStopwatchLog> requestStopwatchLog({int afterSid = 0}) async {
    logRequests++;
    if (pendingLog != null) return pendingLog!.future;
    return entries.where((entry) => entry.sid! > afterSid).firstOrNull ??
        const WatchStopwatchLog(boot: 41);
  }

  void emitLog(String value) => logStream.add(value);
  @override
  Stream<WatchLinkState> get linkStates => links.stream;
  @override
  Stream<String> get logs => logStream.stream;
  @override
  Stream<WatchSnapshot> get snapshots => samples.stream;
  @override
  bool get isConnected => true;
  @override
  Future<void> connect(String address) async {}
  @override
  Future<void> disconnect() async {
    links.add(WatchLinkState.disconnected);
  }

  @override
  Future<void> requestSnapshot() async {}
  @override
  Future<void> syncClock(DateTime time) async {}
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<List<WatchDevice>> pairedDevices() async => [];
  @override
  Future<void> dispose() async {
    await links.close();
    await logStream.close();
    await samples.close();
  }
}

class _Health implements HealthHistoryRepository {
  @override
  Future<void> save(WatchSnapshot snapshot) async {}
  @override
  Future<void> pruneBefore(DateTime cutoff) async {}
  @override
  Future<List<WatchSnapshot>> recent({
    DateTime? since,
    int limit = 50000,
  }) async => [];
  @override
  Future<void> dispose() async {}
}

class _MemoryDatabase implements Database {
  final rows = <String, Map<String, Object?>>{};
  ConflictAlgorithm? lastConflict;
  Map<String, Object?>? lastUpdate;
  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    lastConflict = conflictAlgorithm;
    final key = values['record_key']! as String;
    if (!rows.containsKey(key) ||
        conflictAlgorithm != ConflictAlgorithm.ignore) {
      rows[key] = Map.of(values);
    }
    return 1;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async => rows.values.toList();
  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    lastUpdate = values;
    rows[whereArgs!.single]!.addAll(values);
    return 1;
  }

  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
