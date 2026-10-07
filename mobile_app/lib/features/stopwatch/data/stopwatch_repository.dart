import 'package:sqflite/sqflite.dart';

import '../domain/watch_companion.dart';

abstract interface class StopwatchRepository {
  Future<void> upsert(StopwatchRecord record);
  Future<List<StopwatchRecord>> recent();
  Future<void> annotate(String key, StopwatchTag tag, String note);
  Future<void> dispose();
}

class SqliteStopwatchRepository implements StopwatchRepository {
  SqliteStopwatchRepository({Database? database}) : _database = database;

  Database? _database;
  Future<Database>? _opening;

  Future<Database> get _db async =>
      _database ??= await (_opening ??= openDatabase(
        'ov_stopwatch.db',
        version: 1,
        onCreate: (db, version) => db.execute('''
      CREATE TABLE stopwatch_records (
        record_key TEXT PRIMARY KEY,
        device_address TEXT NOT NULL,
        device_name TEXT NOT NULL,
        boot INTEGER NOT NULL,
        sid INTEGER NOT NULL,
        ended_at INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL,
        imported_at INTEGER NOT NULL,
        tag TEXT NOT NULL,
        note TEXT NOT NULL
      )
    '''),
      ));

  @override
  Future<void> upsert(StopwatchRecord record) async {
    final db = await _db;
    // Never replace a reimported record: its user annotations must survive.
    await db.insert(
      'stopwatch_records',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<List<StopwatchRecord>> recent() async {
    final db = await _db;
    final rows = await db.query(
      'stopwatch_records',
      orderBy: 'ended_at DESC, imported_at DESC',
    );
    return rows.map(StopwatchRecord.fromMap).toList(growable: false);
  }

  @override
  Future<void> annotate(String key, StopwatchTag tag, String note) async {
    if (note.length > 240) throw const FormatException('备注最多 240 字');
    final db = await _db;
    await db.update(
      'stopwatch_records',
      {'tag': tag.name, 'note': note.trim()},
      where: 'record_key = ?',
      whereArgs: [key],
    );
  }

  @override
  Future<void> dispose() async {
    final db = _database ?? await _opening;
    await db?.close();
    _database = null;
    _opening = null;
  }
}
