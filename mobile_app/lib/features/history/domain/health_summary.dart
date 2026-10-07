import '../../watch/domain/watch_snapshot.dart';

enum HealthMetric {
  heartRate('心率', '次/分'),
  steps('步数', '步'),
  temperature('环境温度', '°C'),
  humidity('环境湿度', '%');

  const HealthMetric(this.label, this.unit);

  final String label;
  final String unit;

  /// Zero heart rate means that no measurement is available. The current
  /// protocol has no validity flag for environment readings, so zero remains
  /// a possible environment value, not an invented missing-value marker.
  int? valueOf(WatchSnapshot sample) => switch (this) {
    heartRate => sample.heartRate > 0 ? sample.heartRate : null,
    steps => sample.steps >= 0 ? sample.steps : null,
    temperature =>
      sample.temperature >= -40 && sample.temperature <= 85
          ? sample.temperature
          : null,
    humidity =>
      sample.humidity >= 0 && sample.humidity <= 100 ? sample.humidity : null,
  };
}

class HealthTrendPoint {
  const HealthTrendPoint({
    required this.time,
    required this.value,
    required this.sampleCount,
  });

  final DateTime time;
  final double value;
  final int sampleCount;
}

class HealthSummary {
  HealthSummary._({
    required this.samples,
    required this.metric,
    required this.validCount,
    required this.average,
    required this.minimum,
    required this.maximum,
    required this.dailyStepMaxima,
    required this.totalRecordedSteps,
    required this.goalDays,
    required this.points,
  });

  factory HealthSummary.calculate({
    required Iterable<WatchSnapshot> samples,
    required HealthMetric metric,
    required DateTime start,
    required DateTime end,
    int stepGoal = 8000,
  }) {
    final selected =
        samples
            .where(
              (sample) =>
                  !sample.capturedAt.isBefore(start) &&
                  !sample.capturedAt.isAfter(end),
            )
            .toList()
          ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    final values = <int>[];
    final dailySteps = <DateTime, int>{};
    for (final sample in selected) {
      final value = metric.valueOf(sample);
      if (value != null) values.add(value);
      if (sample.steps < 0) continue;
      // Watch clocks can be wrong before synchronization. Phone capture time
      // is the only reliable day boundary for locally collected history.
      final time = sample.capturedAt.toLocal();
      final day = DateTime(time.year, time.month, time.day);
      final previous = dailySteps[day];
      if (previous == null || sample.steps > previous) {
        dailySteps[day] = sample.steps;
      }
    }
    final sorted = values.toList()..sort();
    return HealthSummary._(
      samples: List.unmodifiable(selected),
      metric: metric,
      validCount: values.length,
      average: values.isEmpty
          ? null
          : values.fold<int>(0, (sum, value) => sum + value) / values.length,
      minimum: sorted.isEmpty ? null : sorted.first,
      maximum: sorted.isEmpty ? null : sorted.last,
      dailyStepMaxima: Map.unmodifiable(dailySteps),
      totalRecordedSteps: dailySteps.values.fold(
        0,
        (sum, value) => sum + value,
      ),
      goalDays: stepGoal <= 0
          ? 0
          : dailySteps.values.where((steps) => steps >= stepGoal).length,
      points: List.unmodifiable(
        metric == HealthMetric.steps
            ? [
                for (final day in dailySteps.entries)
                  HealthTrendPoint(
                    time: day.key,
                    value: day.value.toDouble(),
                    sampleCount: 1,
                  ),
              ]
            : _sensorPoints(selected, metric, start, end),
      ),
    );
  }

  final List<WatchSnapshot> samples;
  final HealthMetric metric;
  final int validCount;
  final double? average;
  final int? minimum;
  final int? maximum;
  final Map<DateTime, int> dailyStepMaxima;
  final int totalRecordedSteps;
  final int goalDays;
  final List<HealthTrendPoint> points;

  /// Exports the actual captured samples, not interpolated chart values.
  /// Unsupported SpO2 is deliberately absent, even when old rows contain 99.
  String toCsv() {
    final rows = <String>[
      'captured_at_utc,watch_time_reported,steps_cumulative,heart_rate_bpm,'
          'ambient_temperature_c,ambient_humidity_percent',
    ];
    for (final sample in samples) {
      rows.add(
        [
          sample.capturedAt.toUtc().toIso8601String(),
          sample.watchTime.toIso8601String(),
          HealthMetric.steps.valueOf(sample) ?? '',
          HealthMetric.heartRate.valueOf(sample) ?? '',
          HealthMetric.temperature.valueOf(sample) ?? '',
          HealthMetric.humidity.valueOf(sample) ?? '',
        ].join(','),
      );
    }
    return '${rows.join('\r\n')}\r\n';
  }
}

List<HealthTrendPoint> _sensorPoints(
  List<WatchSnapshot> samples,
  HealthMetric metric,
  DateTime start,
  DateTime end,
) {
  // Keep raw observations for small collections. Larger sets are reduced to
  // at most 72 occupied time buckets. Empty buckets never become zero values.
  final valid = samples.where((item) => metric.valueOf(item) != null).toList();
  if (valid.length <= 72 || !end.isAfter(start)) {
    return [
      for (final sample in valid)
        HealthTrendPoint(
          time: sample.capturedAt,
          value: metric.valueOf(sample)!.toDouble(),
          sampleCount: 1,
        ),
    ];
  }
  final sums = <int, int>{};
  final counts = <int, int>{};
  final width = end.difference(start).inMilliseconds / 72;
  for (final sample in valid) {
    final bucket = (sample.capturedAt.difference(start).inMilliseconds / width)
        .floor()
        .clamp(0, 71);
    sums[bucket] = (sums[bucket] ?? 0) + metric.valueOf(sample)!;
    counts[bucket] = (counts[bucket] ?? 0) + 1;
  }
  return [
    for (final bucket in sums.keys.toList()..sort())
      HealthTrendPoint(
        time: start.add(
          Duration(milliseconds: ((bucket + 0.5) * width).round()),
        ),
        value: sums[bucket]! / counts[bucket]!,
        sampleCount: counts[bucket]!,
      ),
  ];
}
