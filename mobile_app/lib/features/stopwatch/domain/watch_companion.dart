/// Optional commands implemented by companion-capable watch firmware.
abstract interface class WatchCompanionTransport {
  /// Null means the connected firmware did not answer the capability probe.
  Future<WatchCapabilities?> requestCapabilities();
  Future<WatchStopwatchSnapshot> requestStopwatch();
  Future<WatchStopwatchLog> requestStopwatchLog({int afterSid = 0});
}

class WatchCapabilities {
  const WatchCapabilities({
    required this.data,
    required this.clock,
    required this.clockSyncEnabled,
    required this.stopwatch,
    required this.stopwatchLog,
    required this.logCapacity,
    required this.persistent,
  });

  final bool data;
  final bool clock;
  final bool clockSyncEnabled;
  final bool stopwatch;
  final bool stopwatchLog;
  final int logCapacity;
  final bool persistent;

  factory WatchCapabilities.parse(String line) {
    final fields = _fields(line, 'OVCAP');
    return WatchCapabilities(
      data: _flag(fields, 'data'),
      clock: _flag(fields, 'clock'),
      clockSyncEnabled: _flag(fields, 'clock_sync'),
      stopwatch: _flag(fields, 'sw'),
      stopwatchLog: _flag(fields, 'swlog'),
      logCapacity: _uint(fields, 'swlog_cap', 65535),
      persistent: _flag(fields, 'persist'),
    );
  }
}

enum WatchStopwatchState { idle, run, pause }

class WatchStopwatchSnapshot {
  const WatchStopwatchSnapshot({
    required this.boot,
    required this.sid,
    required this.state,
    required this.elapsedMs,
  });

  final int boot;
  final int sid;
  final WatchStopwatchState state;
  final int elapsedMs;

  factory WatchStopwatchSnapshot.parse(String line) {
    final fields = _fields(line, 'OVSW');
    final state = switch (fields['state']) {
      'idle' => WatchStopwatchState.idle,
      'run' => WatchStopwatchState.run,
      'pause' => WatchStopwatchState.pause,
      _ => throw const FormatException('无效秒表状态'),
    };
    final sid = _uint(fields, 'sid', 0xffffffff);
    if (state != WatchStopwatchState.idle && sid == 0) {
      throw const FormatException('运行中的秒表缺少记录编号');
    }
    return WatchStopwatchSnapshot(
      boot: _uint(fields, 'boot', 0xffffffff),
      sid: sid,
      state: state,
      elapsedMs: _uint(fields, 'elapsed_ms', 0xffffffff),
    );
  }
}

class WatchStopwatchLog {
  const WatchStopwatchLog({
    required this.boot,
    this.sid,
    this.endedAt,
    this.durationMs,
    this.more = false,
  });

  final int boot;
  final int? sid;

  /// Watch RTC calendar fields held in UTC to avoid phone timezone conversion.
  /// This is not a measured UTC instant; display the fields without toLocal().
  final DateTime? endedAt;
  final int? durationMs;
  final bool more;
  bool get isEmpty => sid == null;

  factory WatchStopwatchLog.parse(String line) {
    final fields = _fields(line, 'OVSL');
    final boot = _uint(fields, 'boot', 0xffffffff);
    if (fields.containsKey('none')) {
      if (fields['none'] != '1' || fields.length != 2) {
        throw const FormatException('无效空记录');
      }
      return WatchStopwatchLog(boot: boot);
    }
    final sid = _uint(fields, 'sid', 0xffffffff);
    if (sid == 0) throw const FormatException('无效记录编号');
    return WatchStopwatchLog(
      boot: boot,
      sid: sid,
      endedAt: _date(fields['end']),
      durationMs: _uint(fields, 'dur_ms', 0xffffffff),
      more: _flag(fields, 'more'),
    );
  }
}

Map<String, String> _fields(String line, String type) {
  final parts = line.trim().split('|');
  if (parts.length < 3 || parts[0] != type || parts[1] != '1') {
    throw const FormatException('不支持的手表协议');
  }
  final result = <String, String>{};
  for (final part in parts.skip(2)) {
    final pair = part.split('=');
    if (pair.length != 2 ||
        pair[0].isEmpty ||
        pair[1].isEmpty ||
        result.containsKey(pair[0])) {
      throw const FormatException('手表数据字段不完整或重复');
    }
    result[pair[0]] = pair[1];
  }
  return result;
}

int _uint(Map<String, String> fields, String key, int max) {
  final raw = fields[key];
  if (raw == null || !RegExp(r'^\d+$').hasMatch(raw)) {
    throw FormatException('无效字段 $key');
  }
  final value = int.tryParse(raw);
  if (value == null || value > max) throw FormatException('字段越界 $key');
  return value;
}

bool _flag(Map<String, String> fields, String key) => switch (fields[key]) {
  '0' => false,
  '1' => true,
  _ => throw FormatException('无效开关 $key'),
};

DateTime _date(String? raw) {
  if (raw == null || !RegExp(r'^\d{8}T\d{6}$').hasMatch(raw)) {
    throw const FormatException('无效手表日期');
  }
  final year = int.parse(raw.substring(0, 4));
  final month = int.parse(raw.substring(4, 6));
  final day = int.parse(raw.substring(6, 8));
  final hour = int.parse(raw.substring(9, 11));
  final minute = int.parse(raw.substring(11, 13));
  final second = int.parse(raw.substring(13, 15));
  // RTC carries no timezone. UTC is only a timezone-independent container.
  final date = DateTime.utc(year, month, day, hour, minute, second);
  if (year < 2000 ||
      year > 2099 ||
      date.year != year ||
      date.month != month ||
      date.day != day ||
      date.hour != hour ||
      date.minute != minute ||
      date.second != second) {
    throw const FormatException('手表日期超出范围');
  }
  return date;
}

enum StopwatchTag {
  exercise('运动'),
  study('学习'),
  other('其他');

  const StopwatchTag(this.label);
  final String label;
}

class StopwatchRecord {
  const StopwatchRecord({
    required this.deviceAddress,
    required this.deviceName,
    required this.boot,
    required this.sid,
    required this.endedAt,
    required this.durationMs,
    required this.importedAt,
    this.tag = StopwatchTag.other,
    this.note = '',
  });

  final String deviceAddress;
  final String deviceName;
  final int boot;
  final int sid;

  /// Raw watch RTC calendar fields, not a real UTC instant. Parsed/stored values
  /// use a UTC container; never call toLocal() when displaying watch dates.
  final DateTime endedAt;
  final int durationMs;
  final DateTime importedAt;
  final StopwatchTag tag;
  final String note;

  // End and duration protect old records if a watch loses its boot counter.
  // Encode RTC fields, not the phone-local epoch, so timezone changes cannot
  // change the identity or sort value of a reimported watch record.
  String get key =>
      '$deviceAddress/$boot/$sid/${_rtcContainer(endedAt).millisecondsSinceEpoch}/$durationMs';

  StopwatchRecord annotate(StopwatchTag tag, String note) => StopwatchRecord(
    deviceAddress: deviceAddress,
    deviceName: deviceName,
    boot: boot,
    sid: sid,
    endedAt: endedAt,
    durationMs: durationMs,
    importedAt: importedAt,
    tag: tag,
    note: note,
  );

  Map<String, Object?> toMap() => {
    'record_key': key,
    'device_address': deviceAddress,
    'device_name': deviceName,
    'boot': boot,
    'sid': sid,
    'ended_at': _rtcContainer(endedAt).millisecondsSinceEpoch,
    'duration_ms': durationMs,
    'imported_at': importedAt.millisecondsSinceEpoch,
    'tag': tag.name,
    'note': note,
  };

  factory StopwatchRecord.fromMap(Map<String, Object?> row) => StopwatchRecord(
    deviceAddress: row['device_address']! as String,
    deviceName: row['device_name']! as String,
    boot: row['boot']! as int,
    sid: row['sid']! as int,
    endedAt: DateTime.fromMillisecondsSinceEpoch(
      row['ended_at']! as int,
      isUtc: true,
    ),
    durationMs: row['duration_ms']! as int,
    importedAt: DateTime.fromMillisecondsSinceEpoch(row['imported_at']! as int),
    tag: StopwatchTag.values.byName(row['tag']! as String),
    note: row['note']! as String,
  );
}

DateTime _rtcContainer(DateTime value) => DateTime.utc(
  value.year,
  value.month,
  value.day,
  value.hour,
  value.minute,
  value.second,
);
