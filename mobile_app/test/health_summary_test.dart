import 'package:flutter_test/flutter_test.dart';
import 'package:ov_watch_app/features/history/domain/health_summary.dart';
import 'package:ov_watch_app/features/watch/domain/watch_snapshot.dart';

void main() {
  final start = DateTime(2026, 10, 1);
  final end = DateTime(2026, 10, 8);

  test('steps use the maximum per phone day, never the sum of samples', () {
    final summary = HealthSummary.calculate(
      samples: [
        _sample(DateTime(2026, 10, 2, 18), steps: 3500),
        _sample(DateTime(2026, 10, 1, 12), steps: 9000),
        _sample(DateTime(2026, 10, 1, 13), steps: 100),
        _sample(DateTime(2026, 10, 1, 11), steps: 8000),
      ],
      metric: HealthMetric.steps,
      start: start,
      end: end,
      stepGoal: 8000,
    );
    expect(summary.totalRecordedSteps, 12500);
    expect(summary.dailyStepMaxima[DateTime(2026, 10, 1)], 9000);
    expect(summary.goalDays, 1);
    expect(summary.points.map((point) => point.value), [9000, 3500]);
    // All watch clocks deliberately belong to a different date.
    expect(summary.dailyStepMaxima.containsKey(DateTime(2020, 1, 1)), isFalse);
  });

  test(
    'heart rate zero and samples outside the selected interval are excluded',
    () {
      final summary = HealthSummary.calculate(
        samples: [
          _sample(start.subtract(const Duration(seconds: 1)), heartRate: 200),
          _sample(start, heartRate: 0),
          _sample(start.add(const Duration(minutes: 1)), heartRate: 60),
          _sample(end, heartRate: 100),
          _sample(end.add(const Duration(seconds: 1)), heartRate: 200),
        ],
        metric: HealthMetric.heartRate,
        start: start,
        end: end,
      );
      expect(summary.samples.length, 3);
      expect(summary.validCount, 2);
      expect(summary.average, 80);
      expect(summary.minimum, 60);
      expect(summary.maximum, 100);
      expect(summary.points.length, 2);
    },
  );

  test(
    'empty or unmeasured history does not manufacture a trend or average',
    () {
      final summary = HealthSummary.calculate(
        samples: [_sample(start, heartRate: 0)],
        metric: HealthMetric.heartRate,
        start: start,
        end: end,
      );
      expect(summary.average, isNull);
      expect(summary.minimum, isNull);
      expect(summary.maximum, isNull);
      expect(summary.points, isEmpty);
    },
  );

  test(
    'environment values preserve plausible zero and negative temperatures',
    () {
      final samples = [
        _sample(start, temperature: -5, humidity: 0),
        _sample(
          start.add(const Duration(minutes: 1)),
          temperature: 0,
          humidity: 100,
        ),
        _sample(
          start.add(const Duration(minutes: 2)),
          temperature: 255,
          humidity: 255,
        ),
      ];
      final temperature = HealthSummary.calculate(
        samples: samples,
        metric: HealthMetric.temperature,
        start: start,
        end: end,
      );
      final humidity = HealthSummary.calculate(
        samples: samples,
        metric: HealthMetric.humidity,
        start: start,
        end: end,
      );
      expect(temperature.average, -2.5);
      expect(temperature.validCount, 2);
      expect(humidity.average, 50);
      expect(humidity.validCount, 2);
    },
  );

  test('CSV exports raw samples and leaves unsupported blood oxygen out', () {
    final summary = HealthSummary.calculate(
      samples: [_sample(start, heartRate: 0, spo2: 99)],
      metric: HealthMetric.steps,
      start: start,
      end: end,
    );
    final csv = summary.toCsv();
    expect(
      csv,
      startsWith('captured_at_utc,watch_time_reported,steps_cumulative,'),
    );
    expect(
      csv,
      contains('heart_rate_bpm,ambient_temperature_c,ambient_humidity_percent'),
    );
    expect(csv, contains(',2000,,25,50\r\n'));
    expect(csv.toLowerCase(), isNot(contains('spo2')));
    expect(csv, isNot(contains(',99')));
    expect(csv, contains(start.toUtc().toIso8601String()));
  });

  test(
    'dense sensor collections have bounded points and no empty bucket values',
    () {
      final summary = HealthSummary.calculate(
        samples: [
          for (var i = 0; i < 500; i++)
            _sample(start.add(Duration(minutes: i)), heartRate: 80),
        ],
        metric: HealthMetric.heartRate,
        start: start,
        end: end,
      );
      expect(summary.validCount, 500);
      expect(summary.points.length, lessThanOrEqualTo(72));
      expect(summary.points.every((point) => point.value == 80), isTrue);
      expect(
        summary.points.fold<int>(0, (sum, point) => sum + point.sampleCount),
        500,
      );
    },
  );
}

WatchSnapshot _sample(
  DateTime at, {
  int steps = 2000,
  int heartRate = 80,
  int temperature = 25,
  int humidity = 50,
  int? spo2,
}) => WatchSnapshot(
  capturedAt: at,
  watchTime: DateTime(2020, 1, 1),
  steps: steps,
  heartRate: heartRate,
  temperature: temperature,
  humidity: humidity,
  spo2: spo2,
);
