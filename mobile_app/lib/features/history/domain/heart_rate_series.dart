import '../../watch/domain/watch_snapshot.dart';

class HeartRatePoint {
  const HeartRatePoint({
    required this.bucketIndex,
    required this.average,
    required this.start,
  });

  final int bucketIndex;
  final double average;
  final DateTime start;
}

List<HeartRatePoint> aggregateHeartRate({
  required List<WatchSnapshot> samples,
  required DateTime start,
  required DateTime end,
  int bucketCount = 60,
}) {
  if (bucketCount <= 0 || !end.isAfter(start)) return const [];

  final durationMs = end.difference(start).inMilliseconds;
  final sums = <int, int>{};
  final counts = <int, int>{};

  for (final sample in samples) {
    if (sample.heartRate <= 0 ||
        sample.capturedAt.isBefore(start) ||
        sample.capturedAt.isAfter(end)) {
      continue;
    }
    final elapsedMs = sample.capturedAt.difference(start).inMilliseconds;
    final index = (elapsedMs * bucketCount ~/ durationMs).clamp(
      0,
      bucketCount - 1,
    );
    sums[index] = (sums[index] ?? 0) + sample.heartRate;
    counts[index] = (counts[index] ?? 0) + 1;
  }

  final bucketMs = durationMs / bucketCount;
  return [
    for (final index in sums.keys.toList()..sort())
      HeartRatePoint(
        bucketIndex: index,
        average: sums[index]! / counts[index]!,
        start: start.add(Duration(milliseconds: (bucketMs * index).round())),
      ),
  ];
}
