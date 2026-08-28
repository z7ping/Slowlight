import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/local_db.dart';

/// 本机迁移留痕。只保存摘要、可重试快照和错误摘要，不保存 Secret。
class LocalMigrationReportStore {
  Future<Database> _database() async {
    final db = await LocalDb().database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS migration_reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        conflict_policy TEXT NOT NULL,
        snapshot TEXT NOT NULL DEFAULT '{}',
        scanned TEXT NOT NULL DEFAULT '{}',
        created TEXT NOT NULL DEFAULT '{}',
        status TEXT NOT NULL,
        error_summary TEXT NOT NULL DEFAULT '',
        server_report_id INTEGER
      )
    ''');
    for (final column in const [
      'updated_at TEXT NOT NULL DEFAULT \'\'',
      'snapshot TEXT NOT NULL DEFAULT \'{}\'',
      'scanned TEXT NOT NULL DEFAULT \'{}\'',
      'error_summary TEXT NOT NULL DEFAULT \'\'',
    ]) {
      try {
        await db.execute('ALTER TABLE migration_reports ADD COLUMN $column');
      } on DatabaseException {
        // 已存在的列无需处理；兼容此前狗粮阶段创建的简版表。
      }
    }
    return db;
  }

  Future<int> start(Map<String, dynamic> snapshot, String policy) async {
    final db = await _database();
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('migration_reports', {
      'created_at': now,
      'updated_at': now,
      'conflict_policy': policy,
      'snapshot': jsonEncode(snapshot),
      'scanned': jsonEncode(_scanned(snapshot)),
      'created': '{}',
      'status': 'running',
      'error_summary': '',
    });
  }

  Future<void> succeed(int id, Map<String, dynamic> result) async {
    final db = await _database();
    await db.update(
        'migration_reports',
        {
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'created': jsonEncode(result['created'] ?? {}),
          'status': 'succeeded',
          'error_summary': '',
          'server_report_id': result['report']?['id'],
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  Future<void> fail(int id, Object error) async {
    final db = await _database();
    await db.update(
        'migration_reports',
        {
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'status': 'failed',
          'error_summary': _summary(error),
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> retrySnapshot(int id) async {
    final db = await _database();
    final rows = await db.query('migration_reports',
        where: 'id = ? AND status = ?', whereArgs: [id, 'failed'], limit: 1);
    if (rows.isEmpty) return null;
    final raw = rows.first['snapshot']?.toString() ?? '{}';
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<List<Map<String, dynamic>>> all() async {
    final db = await _database();
    return (await db.query('migration_reports',
            orderBy: 'created_at DESC', limit: 20))
        .map((row) => {...Map<String, dynamic>.from(row), 'source': 'local'})
        .toList();
  }

  Map<String, int> _scanned(Map<String, dynamic> snapshot) => {
        for (final key in const [
          'lists',
          'tags',
          'system_tags',
          'habits',
          'tasks',
          'subtasks',
          'habit_logs',
          'sessions'
        ])
          key: (snapshot[key] as List?)?.length ?? 0,
      };

  String _summary(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    return text.length > 300 ? '${text.substring(0, 300)}…' : text;
  }
}
