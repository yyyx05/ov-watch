import 'package:sqflite/sqflite.dart';

import '../../watch/domain/watch_snapshot.dart';
import '../../watch/domain/watch_preferences.dart';
import '../../watch/domain/watch_transport.dart';

abstract interface class HealthHistoryRepository {
  Future<void> save(WatchSnapshot snapshot);
  Future<List<WatchSnapshot>> recent({DateTime? since, int limit = 50000});
  Future<void> pruneBefore(DateTime cutoff);
  Future<void> dispose();
}

class SqliteHealthHistoryRepository
    implements HealthHistoryRepository, WatchPreferencesRepository {
  Database? _database;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;

    final database = await openDatabase(
      'ov_watch.db',
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE health_samples (
            captured_at INTEGER PRIMARY KEY,
            watch_time INTEGER NOT NULL,
            steps INTEGER NOT NULL,
            heart_rate INTEGER NOT NULL,
            temperature INTEGER NOT NULL,
            humidity INTEGER NOT NULL,
            spo2 INTEGER
          )
        ''');
        await _createPreferences(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createPreferences(db);
      },
    );
    _database = database;
    return database;
  }

  static Future<void> _createPreferences(Database db) => db.execute('''
    CREATE TABLE app_preferences (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');

  @override
  Future<WatchPreferences> loadPreferences() async {
    final db = await _db;
    final rows = await db.query('app_preferences');
    final values = {
      for (final row in rows) row['key']! as String: row['value']! as String,
    };
    final goal = int.tryParse(values['step_goal'] ?? '') ?? 8000;
    final address = values['preferred_address'];
    return WatchPreferences(
      stepGoal: goal >= 1000 && goal <= 50000 ? goal : 8000,
      preferredDevice: address == null
          ? null
          : WatchDevice(
              name: values['preferred_name'] ?? 'OV-Watch',
              address: address,
            ),
    );
  }

  @override
  Future<void> saveStepGoal(int value) async {
    final db = await _db;
    await db.insert('app_preferences', {
      'key': 'step_goal',
      'value': '$value',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> savePreferredDevice(WatchDevice device) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final entry in {
        'preferred_address': device.address,
        'preferred_name': device.name,
      }.entries) {
        await txn.insert('app_preferences', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  @override
  Future<void> save(WatchSnapshot snapshot) async {
    final db = await _db;
    await db.insert(
      'health_samples',
      snapshot.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<WatchSnapshot>> recent({
    DateTime? since,
    int limit = 50000,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'health_samples',
      where: since == null ? null : 'captured_at >= ?',
      whereArgs: since == null ? null : [since.millisecondsSinceEpoch],
      orderBy: 'captured_at DESC',
      limit: limit,
    );
    return rows
        .map(WatchSnapshot.fromMap)
        .toList(growable: false)
        .reversed
        .toList();
  }

  @override
  Future<void> pruneBefore(DateTime cutoff) async {
    final db = await _db;
    await db.delete(
      'health_samples',
      where: 'captured_at < ?',
      whereArgs: [cutoff.millisecondsSinceEpoch],
    );
  }

  @override
  Future<void> dispose() async {
    await _database?.close();
    _database = null;
  }
}
