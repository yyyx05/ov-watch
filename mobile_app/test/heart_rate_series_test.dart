import 'package:flutter_test/flutter_test.dart';
import 'package:ov_watch_app/features/history/domain/heart_rate_series.dart';
import 'package:ov_watch_app/features/watch/domain/watch_snapshot.dart';

void main() {
  test('aggregates valid heart-rate samples into time buckets', () {
    final start = DateTime(2026, 10, 2);
    final end = start.add(const Duration(hours: 1));
    final points = aggregateHeartRate(
      start: start,
      end: end,
      bucketCount: 6,
      samples: [
        _snapshot(start.add(const Duration(minutes: 1)), heartRate: 60),
        _snapshot(start.add(const Duration(minutes: 9)), heartRate: 80),
        _snapshot(start.add(const Duration(minutes: 11)), heartRate: 90),
        _snapshot(start.add(const Duration(minutes: 22)), heartRate: 0),
      ],
    );

    expect(points, hasLength(2));
    expect(points[0].bucketIndex, 0);
    expect(points[0].average, 70);
    expect(points[1].bucketIndex, 1);
    expect(points[1].average, 90);
  });

  test('ignores samples outside the selected range', () {
    final start = DateTime(2026, 10, 2);
    final end = start.add(const Duration(days: 1));

    final points = aggregateHeartRate(
      start: start,
      end: end,
      samples: [
        _snapshot(start.subtract(const Duration(seconds: 1)), heartRate: 70),
        _snapshot(end.add(const Duration(seconds: 1)), heartRate: 80),
      ],
    );

    expect(points, isEmpty);
  });
}

WatchSnapshot _snapshot(DateTime capturedAt, {required int heartRate}) {
  return WatchSnapshot(
    capturedAt: capturedAt,
    watchTime: capturedAt,
    steps: 100,
    heartRate: heartRate,
    temperature: 25,
    humidity: 60,
  );
}
