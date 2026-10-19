import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/db/local_product_core_schema.dart';
import 'package:slowlight/repositories/tag_links_repository.dart';
import 'package:slowlight/services/data_mode_manager.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  late String dbPath;
  const repository = TagLinksRepository();

  setUpAll(() async {
    dbPath = p.join(await useIsolatedTestDb('tag_links_repository'), 'slowlight_offline.db');
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({'data_mode': 'local'});
    await DataModeManager().setLocal();
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
  });
  tearDown(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
  });

  test('同一组标签跨四种记录复用，去重、清空互不影响', () async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '工作', 'created_at': now, 'updated_at': now,
    });
    final first = await db.insert('tags', {
      'name': '学习', 'created_at': now, 'updated_at': now,
    });
    final second = await db.insert('tags', {
      'name': '编程', 'created_at': now, 'updated_at': now,
    });
    final task = await db.insert('tasks', {
      'list_id': listId, 'title': '任务', 'created_at': now, 'updated_at': now,
    });
    final habit = await db.insert('habits', {
      'name': '习惯', 'created_at': now, 'updated_at': now,
    });
    final session = await db.insert('work_sessions', {
      'session_type': 'work', 'started_at': now, 'created_at': now,
    });
    // 观察记录用现有 reflections，不创建另一套分类数据。
    final observation = await db.insert('reflections', {
      'entry_type': 'observation', 'content': '一次观察',
      'context_json': jsonEncode({}), 'created_at': now, 'updated_at': now,
    });
    final records = [
      (TagRecordKind.task, task),
      (TagRecordKind.habit, habit),
      (TagRecordKind.session, session),
      (TagRecordKind.observation, observation),
    ];
    for (final (kind, recordId) in records) {
      await repository.replace(kind, recordId, [first, second, first]);
      expect(await repository.getTagIds(kind, recordId), [first, second]);
    }
    await repository.replace(TagRecordKind.habit, habit, []);
    expect(await repository.getTagIds(TagRecordKind.habit, habit), isEmpty);
    expect(await repository.getTagIds(TagRecordKind.task, task), [first, second]);
  });

  test('包含不存在的标签时必须全部回滚，不允许部分丢失', () async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '工作', 'created_at': now, 'updated_at': now,
    });
    final first = await db.insert('tags', {
      'name': '已有', 'created_at': now, 'updated_at': now,
    });
    final task = await db.insert('tasks', {
      'list_id': listId, 'title': '任务', 'created_at': now, 'updated_at': now,
    });
    await repository.replace(TagRecordKind.task, task, [first]);
    await expectLater(
      repository.replace(TagRecordKind.task, task, [first, 999999]),
      throwsStateError,
    );
    expect(await repository.getTagIds(TagRecordKind.task, task), [first]);
    await expectLater(
      repository.replace(TagRecordKind.task, -123, []),
      throwsStateError,
    );
    expect(await repository.getTagIds(TagRecordKind.task, task), [first]);
  });
}
