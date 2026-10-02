class WatchSnapshot {
  const WatchSnapshot({
    required this.capturedAt,
    required this.watchTime,
    required this.steps,
    required this.heartRate,
    required this.temperature,
    required this.humidity,
    this.spo2,
  });

  final DateTime capturedAt;
  final DateTime watchTime;
  final int steps;
  final int heartRate;
  final int temperature;
  final int humidity;
  final int? spo2;

  // 当前固件的 SpO2 测量分支未实现，收到的默认值不能视为真实测量。
  bool get hasMeasuredSpo2 => false;

  Map<String, Object?> toMap() => {
    'captured_at': capturedAt.millisecondsSinceEpoch,
    'watch_time': watchTime.millisecondsSinceEpoch,
    'steps': steps,
    'heart_rate': heartRate,
    'temperature': temperature,
    'humidity': humidity,
    'spo2': spo2,
  };

  factory WatchSnapshot.fromMap(Map<String, Object?> map) {
    return WatchSnapshot(
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        map['captured_at']! as int,
      ),
      watchTime: DateTime.fromMillisecondsSinceEpoch(map['watch_time']! as int),
      steps: map['steps']! as int,
      heartRate: map['heart_rate']! as int,
      temperature: map['temperature']! as int,
      humidity: map['humidity']! as int,
      spo2: map['spo2'] as int?,
    );
  }
}
