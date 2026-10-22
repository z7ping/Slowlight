import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// 本地统一标签的增量关联结构。
///
/// tags/task_tags 继续是任务的正式数据结构；旧 system_tags 的 ID
/// 不能直接作为 tags.id 使用，必须经 legacy_system_tag_aliases 映射。
/// 当前只回填历史，不改旧系统字段、同步队列或用户选择器。
abstract final class UnifiedTagSchema {
  static Future<void> ensureTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS legacy_system_tag_aliases (
        system_tag_id INTEGER PRIMARY KEY,
        tag_id INTEGER NOT NULL
      )
    ''');
    for (final spec in <(String, String)>[
      ('habit_tags', 'habit_id'),
      ('work_session_tags', 'work_session_id'),
      ('reflection_tags', 'reflection_id'),
    ]) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${spec.$1} (
          ${spec.$2} INTEGER NOT NULL,
          tag_id INTEGER NOT NULL,
          PRIMARY KEY (${spec.$2}, tag_id)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${spec.$1}_tag_id ON ${spec.$1}(tag_id)',
      );
    }
  }

  /// 只在 Local Data 回填；Cloud Cache 必须等待服务端提供的 canonical ID
  /// 映射，不能把账号缓存的 system_tags 本地行号当作服务器 tag ID。
  static Future<void> backfillLocal(Database db) async {
    await ensureTables(db);
    await db.transaction((txn) async {
      final reflections = await txn.query(
        'reflections',
        columns: ['id', 'context_json'],
        where: "entry_type = 'observation' AND deleted_at IS NULL",
      );
      final reflectionIDs = <int, List<int>>{};
      for (final row in reflections) {
        try {
          final decoded = jsonDecode(row['context_json']?.toString() ?? '{}');
          if (decoded is! Map) continue;
          final raw = decoded['observation_tag_id'];
          final tagId = raw is num ? raw.toInt() : int.tryParse(raw.toString());
          if (tagId == null || tagId <= 0) continue;
          reflectionIDs.putIfAbsent(tagId, () => []).add(row['id'] as int);
        } catch (_) {
          // 历史 context 无法解析时保持原文，不阻塞其他记录升级。
        }
      }

      final legacy = await txn.query('system_tags', orderBy: 'id ASC');
      for (final row in legacy) {
        final oldId = row['id'] as int;
        if ((await txn.query('legacy_system_tag_aliases',
                where: 'system_tag_id = ?', whereArgs: [oldId], limit: 1))
            .isNotEmpty) {
          continue;
        }
        // 管理页可见的默认标签也映射为 canonical 标签供任务选择。
        final name = row['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;

        final matches = await txn.query(
          'tags',
          columns: ['id'],
          where: 'name = ?',
          whereArgs: [name],
          orderBy: 'id ASC',
          limit: 1,
        );
        final tagId = matches.isNotEmpty
            ? matches.first['id'] as int
            : await txn.insert('tags', {
                'name': name,
                'color': row['color'] ?? '#0075de',
                'created_at': row['created_at'],
                'updated_at': row['updated_at'],
              });
        await txn.insert('legacy_system_tag_aliases', {
          'system_tag_id': oldId,
          'tag_id': tagId,
        });

        for (final spec in <(String, String)>[
          ('tasks', 'task_tags'),
          ('habits', 'habit_tags'),
          ('work_sessions', 'work_session_tags'),
        ]) {
          final rows = await txn.query(
            spec.$1,
            columns: ['id'],
            where: 'system_tag_id = ?',
            whereArgs: [oldId],
          );
          final linkKey = switch (spec.$1) {
            'tasks' => 'task_id',
            'habits' => 'habit_id',
            _ => 'work_session_id',
          };
          for (final link in rows) {
            await txn.insert(
              spec.$2,
              {linkKey: link['id'], 'tag_id': tagId},
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
        for (final id in reflectionIDs[oldId] ?? const <int>[]) {
          await txn.insert(
            'reflection_tags',
            {'reflection_id': id, 'tag_id': tagId},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    });
  }
}
