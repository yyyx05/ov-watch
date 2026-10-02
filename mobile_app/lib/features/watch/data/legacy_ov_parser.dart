import '../domain/watch_snapshot.dart';

/// Reassembles the current multi-line `OV+SEND` response.
///
/// Bluetooth RFCOMM is a byte stream, so a UART print call is not guaranteed to
/// arrive as one Android read. The transport splits CRLF lines first, then this
/// parser builds a complete snapshot ending at `Step today:`.
class LegacyOvParser {
  int? _month;
  int? _day;
  int? _hour;
  int? _minute;
  int? _second;
  int? _humidity;
  int? _temperature;
  int? _heartRate;
  int? _spo2;

  WatchSnapshot? addLine(String rawLine, {DateTime? receivedAt}) {
    final line = rawLine.trim();
    if (line.isEmpty) return null;

    if (line == 'RecStr:OV+SEND' || line.startsWith('data:')) {
      _reset();
    }

    final date = RegExp(r'^data:\s*(\d{1,2})-(\d{1,2})$').firstMatch(line);
    if (date != null) {
      _month = int.parse(date.group(1)!);
      _day = int.parse(date.group(2)!);
      return null;
    }

    final time = RegExp(
      r'^time:(\d{1,2}):(\d{1,2}):(\d{1,2})$',
    ).firstMatch(line);
    if (time != null) {
      _hour = int.parse(time.group(1)!);
      _minute = int.parse(time.group(2)!);
      _second = int.parse(time.group(3)!);
      return null;
    }

    _humidity = _readInt(line, 'humidity:', suffix: '%') ?? _humidity;
    _temperature = _readInt(line, 'temperature:') ?? _temperature;
    _heartRate = _readInt(line, 'Heart Rate:', suffix: '%') ?? _heartRate;
    _spo2 = _readInt(line, 'SPO2:', suffix: '%') ?? _spo2;

    final steps = _readInt(line, 'Step today:');
    if (steps == null) return null;

    final now = receivedAt ?? DateTime.now();
    final watchTime = DateTime(
      now.year,
      _month ?? now.month,
      _day ?? now.day,
      _hour ?? now.hour,
      _minute ?? now.minute,
      _second ?? now.second,
    );

    final snapshot = WatchSnapshot(
      capturedAt: now,
      watchTime: watchTime,
      steps: steps,
      heartRate: _heartRate ?? 0,
      temperature: _temperature ?? 0,
      humidity: _humidity ?? 0,
      spo2: _spo2,
    );
    _reset();
    return snapshot;
  }

  int? _readInt(String line, String prefix, {String suffix = ''}) {
    final pattern =
        '^${RegExp.escape(prefix)}\\s*(-?\\d+)${RegExp.escape(suffix)}\$';
    final match = RegExp(pattern).firstMatch(line);
    return match == null ? null : int.parse(match.group(1)!);
  }

  void _reset() {
    _month = null;
    _day = null;
    _hour = null;
    _minute = null;
    _second = null;
    _humidity = null;
    _temperature = null;
    _heartRate = null;
    _spo2 = null;
  }
}
