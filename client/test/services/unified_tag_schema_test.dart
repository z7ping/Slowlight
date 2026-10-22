import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/db/local_product_core_schema.dart';
import 'package:slowlight/db/unified_tag_schema.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  late String dbPath;

  setUpAll(() async {
    dbPath = p.join(
      await useIsolatedTestDb('unified_tag_schema'),
      'slowlight_offline.db',
    );
  });
  setUp(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
  });
  tearDown(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
  });

  test('管理页默认标签也映射为可选 canonical 标签，历史关联幂等', () async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '工作', 'created_at': now, 'updated_at': now,
    });
    final tagId = await db.insert('tags', {
      'name': '学习', 'color': '#abcdef',
      'created_at': now, 'updated_at': now,
    });
    final oldTagId = await db.insert('system_tags', {
      'name': '学习', 'icon': '📚', 'color': '#123456',
      'created_at': now, 'updated_at': now,
    });
    final unusedDefault = await db.insert('system_tags', {
      'name': '身体', 'icon': '💪', 'color': '#52c41a', 'is_default': 1,
      'created_at': now, 'updated_at': now,
    });
    final taskId = await db.insert('tasks', {
      'list_id': listId, 'title': '读书', 'system_tag_id': oldTagId,
      'created_at': now, 'updated_at': now,
    });
    final habitId = await db.insert('habits', {
      'name': '早读', 'system_tag_id': oldTagId,
      'created_at': now, 'updated_at': now,
    });
    final sessionId = await db.insert('work_sessions', {
      'session_type': 'work', 'system_tag_id': oldTagId,
      'started_at': now, 'created_at': now,
    });
    final reflectionId = await db.insert('reflections', {
      'entry_type': 'observation', 'content': '记录事实',
      'context_json': jsonEncode({'observation_tag_id': oldTagId}),
      'created_at': now, 'updated_at': now,
    });

    await LocalProductCoreSchema.ensureReady();
    final aliases = await db.query('legacy_system_tag_aliases');
    expect(aliases, hasLength(2));
    final mapped = {for (final row in aliases) row['system_tag_id']: row['tag_id']};
    expect(mapped[oldTagId], tagId);
    final defaultCanonicalId = mapped[unusedDefault] as int;
    expect(defaultCanonicalId, isNot(tagId));
    final defaults = await db.query('tags',
        where: 'id = ?', whereArgs: [defaultCanonicalId]);
    expect(defaults.single['name'], '身体');
    expect(
      await db.query('legacy_system_tag_aliases',
          where: 'system_tag_id = ?', whereArgs: [unusedDefault]),
      hasLength(1),
    );
    for (final (table, column, id) in [
      ('task_tags', 'task_id', taskId),
      ('habit_tags', 'habit_id', habitId),
      ('work_session_tags', 'work_session_id', sessionId),
      ('reflection_tags', 'reflection_id', reflectionId),
    ]) {
      final links = await db.query(table, where: '$column = ?', whereArgs: [id]);
      expect(links, hasLength(1), reason: table);
      expect(links.single['tag_id'], tagId, reason: table);
    }

    await db.delete('habit_tags', where: 'habit_id = ?', whereArgs: [habitId]);
    await UnifiedTagSchema.backfillLocal(db);
    expect(await db.query('habit_tags', where: 'habit_id = ?', whereArgs: [habitId]), isEmpty);
    expect(
      await db.query('system_tags', where: 'id = ?', whereArgs: [oldTagId]),
      isNotEmpty,
      reason: '历史数据必须保留',
    );
  });

  test('本地关联表重复建表不报错，未关联标签也可保留', () async {
    final db = await LocalDb().database;
    await UnifiedTagSchema.ensureTables(db);
    await UnifiedTagSchema.ensureTables(db);
    for (final table in [
      'legacy_system_tag_aliases', 'habit_tags',
      'work_session_tags', 'reflection_tags',
    ]) {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        [table],
      );
      expect(rows, hasLength(1), reason: table);
    }
  });
}
