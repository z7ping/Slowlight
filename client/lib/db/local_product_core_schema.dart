import 'package:sqflite/sqflite.dart';

import '../models/dimension.dart';
import 'local_db.dart';

/// Slowlight 产品核心领域的迁移。
class LocalProductCoreSchema {
  const LocalProductCoreSchema._();

  static Future<void> ensureReady() async {
    final db = await LocalDb().database;
    await _ensureObservationTagFields(db);
    await _ensureReflections(db);
    await backfillLegacyDimensions(db);
    await _normalizeInstantStorage(db);
  }

  static Future<void> _ensureObservationTagFields(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(system_tags)');
    final names = columns.map((row) => row['name']).toSet();
    if (!names.contains('dimension_key')) {
      await db.execute(
        "ALTER TABLE system_tags ADD COLUMN dimension_key TEXT DEFAULT ''",
      );
    }
    if (!names.contains('is_default')) {
      await db.execute(
        'ALTER TABLE system_tags ADD COLUMN is_default INTEGER DEFAULT 0',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_system_tags_dimension_key '
      'ON system_tags(dimension_key)',
    );
  }

  static Future<void> _ensureReflections(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reflections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        entry_type TEXT NOT NULL DEFAULT 'reflection',
        question_id TEXT,
        dimension_key TEXT,
        content TEXT NOT NULL,
        context_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reflections_created_at '
      'ON reflections(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reflections_dimension '
      'ON reflections(dimension_key)',
    );
  }

  /// 旧版本的四个 SystemTag 继续保留用于兼容历史 system_tag_id，
  /// 但它们只作为默认观察标签，Dimension 身份由稳定 key 表达。
  static Future<void> backfillLegacyDimensions(Database db) async {
    for (final dimension in DimensionCatalog.all) {
      await db.update(
        'system_tags',
        {
          'dimension_key': dimension.keyValue,
          'is_default': 1,
        },
        where: 'name = ?',
        whereArgs: [dimension.name],
      );
    }
  }

  /// 旧版本曾混用本地 ISO 与 UTC ISO。这里一次性把“时间点”字段规范为 UTC。
  /// due_date 与 habit_logs.date 是日历日期，故意不进入迁移。
  static Future<void> _normalizeInstantStorage(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_schema_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    final migrated = await db.query(
      'local_schema_meta',
      where: 'key = ?',
      whereArgs: ['instant_storage_utc_v1'],
      limit: 1,
    );
    if (migrated.isNotEmpty) return;

    const specs = <String, List<String>>{
      'lists': ['created_at', 'updated_at', 'deleted_at'],
      'tasks': [
        'created_at',
        'updated_at',
        'completed_at',
        'reminder_at',
        'deleted_at',
        'last_modified',
      ],
      'subtasks': ['created_at', 'updated_at', 'last_modified'],
      'tags': ['created_at', 'updated_at', 'last_modified'],
      'system_tags': ['created_at', 'updated_at', 'last_modified'],
      'habits': ['created_at', 'updated_at', 'deleted_at', 'last_modified'],
      'habit_logs': ['created_at', 'last_modified'],
      'work_sessions': ['started_at', 'ended_at', 'created_at'],
      'behavior_events': ['occurred_at', 'created_at'],
      'reflections': ['created_at', 'updated_at', 'deleted_at'],
    };

    await db.transaction((txn) async {
      for (final entry in specs.entries) {
        final table = entry.key;
        if (!await _tableExists(txn, table)) continue;
        final columns = await txn.rawQuery('PRAGMA table_info($table)');
        final existing = columns.map((row) => row['name']?.toString()).toSet();
        final instantColumns = entry.value.where(existing.contains).toList();
        if (instantColumns.isEmpty || !existing.contains('id')) continue;

        final rows = await txn.query(table, columns: ['id', ...instantColumns]);
        for (final row in rows) {
          final updates = <String, Object?>{};
          for (final column in instantColumns) {
            final raw = row[column]?.toString();
            if (raw == null || raw.trim().isEmpty) continue;
            final parsed = DateTime.tryParse(raw);
            if (parsed == null) continue;
            final utc = parsed.toUtc().toIso8601String();
            if (utc != raw) updates[column] = utc;
          }
          if (updates.isNotEmpty) {
            await txn.update(
              table,
              updates,
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          }
        }
      }
      await txn.insert(
        'local_schema_meta',
        {'key': 'instant_storage_utc_v1', 'value': 'done'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return rows.isNotEmpty;
  }
}
