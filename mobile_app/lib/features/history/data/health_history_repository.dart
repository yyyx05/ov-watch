import 'package:sqflite/sqflite.dart';

import '../../watch/domain/watch_snapshot.dart';

abstract interface class HealthHistoryRepository {
  Future<void> save(WatchSnapshot snapshot);
  Future<List<WatchSnapshot>> recent({DateTime? since, int limit = 50000});
  Future<void> pruneBefore(DateTime cutoff);
  Future<void> dispose();
}

class SqliteHealthHistoryRepository implements HealthHistoryRepository {
  Database? _database;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;

    final database = await openDatabase(
      'ov_watch.db',
      version: 1,
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
      },
    );
    _database = database;
    return database;
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
