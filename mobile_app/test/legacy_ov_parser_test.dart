import 'package:flutter_test/flutter_test.dart';
import 'package:ov_watch_app/features/watch/data/legacy_ov_parser.dart';
import 'package:ov_watch_app/features/watch/domain/watch_snapshot.dart';

void main() {
  test('parses one complete OV+SEND response', () {
    final parser = LegacyOvParser();
    final receivedAt = DateTime(2026, 10, 2, 13, 0);
    const lines = [
      'RecStr:OV+SEND',
      'data:10-02',
      'time:12:58:06',
      'humidity:61%',
      'temperature:26',
      'Heart Rate:78%',
      'SPO2:99%',
      'Step today:3241',
    ];

    final snapshots = <WatchSnapshot>[];
    for (final line in lines) {
      final snapshot = parser.addLine(line, receivedAt: receivedAt);
      if (snapshot != null) {
        snapshots.add(snapshot);
      }
    }

    expect(snapshots, hasLength(1));
    final snapshot = snapshots.single;
    expect(snapshot.steps, 3241);
    expect(snapshot.heartRate, 78);
    expect(snapshot.temperature, 26);
    expect(snapshot.humidity, 61);
    expect(snapshot.spo2, 99);
    expect(snapshot.hasMeasuredSpo2, isFalse);
    expect(snapshot.watchTime, DateTime(2026, 10, 2, 12, 58, 6));
  });

  test('ignores debug and incomplete lines', () {
    final parser = LegacyOvParser();
    expect(parser.addLine('RecStr:OV'), isNull);
    expect(parser.addLine('OK'), isNull);
    expect(parser.addLine('Heart Rate:82%'), isNull);
  });
}
