import 'watch_transport.dart';

class WatchPreferences {
  const WatchPreferences({this.stepGoal = 8000, this.preferredDevice});

  final int stepGoal;
  final WatchDevice? preferredDevice;
}

abstract interface class WatchPreferencesRepository {
  Future<WatchPreferences> loadPreferences();
  Future<void> saveStepGoal(int value);
  Future<void> savePreferredDevice(WatchDevice device);
}
