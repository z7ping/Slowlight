import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/repositories/observation_tag_repository.dart';
import 'package:slowlight/services/data_mode_manager.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String databasePath;
  setUpAll(() async {
    databasePath = p.join(
      await useIsolatedTestDb('p15_observation_tag'),
      'slowlight_offline.db',
    );
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb().close();
    await databaseFactory.deleteDatabase(databasePath);
    DataModeManager().resetForTesting();
    await DataModeManager().setLocal();
  });
  tearDown(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(databasePath);
  });

  test('X08 本地删除标签必须匹配用户确认的关联数量', () async {
    final repo = ObservationTagRepository();
    final tag = await repo.create(
      name: 'X08 审核标签', icon: '🏷', color: '#1890ff',
    );
    final preview = await repo.getDeletionImpact(tag);
    expect(preview?.tasks, 0);
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '审核清单', 'created_at': now, 'updated_at': now,
    });
    final taskId = await db.insert('tasks', {
      'list_id': listId, 'title': '确认后新增任务',
      'system_tag_id': tag.id, 'created_at': now, 'updated_at': now,
    });
    await expectLater(
      repo.delete(tag, expectedImpact: preview),
      throwsStateError,
    );
    expect(await db.query('system_tags', where: 'id = ?',
      whereArgs: [tag.id]), hasLength(1));
    expect((await db.query('tasks', where: 'id = ?',
      whereArgs: [taskId])).single['system_tag_id'], tag.id);
    final fresh = await repo.getDeletionImpact(tag);
    expect(fresh?.tasks, 1);
    await repo.delete(tag, expectedImpact: fresh);
    expect(await db.query('system_tags', where: 'id = ?',
      whereArgs: [tag.id]), isEmpty);
    expect((await db.query('tasks', where: 'id = ?',
      whereArgs: [taskId])).single['system_tag_id'], isNull);
  });

  test('X08 原标签/别名/统一关联精确恢复，不能重复撤销', () async {
    final repo = ObservationTagRepository();
    final tag = await repo.create(
      name: '可还原标签', icon: '📚', color: '#112233',
    );
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '清单', 'created_at': now, 'updated_at': now,
    });
    final taskId = await db.insert('tasks', {
      'list_id': listId, 'title': '有标签任务',
      'system_tag_id': tag.id, 'created_at': now, 'updated_at': now,
    });
    final habitId = await db.insert('habits', {
      'name': '有标签习惯', 'system_tag_id': tag.id,
      'created_at': now, 'updated_at': now,
    });
    final alias = (await db.query('legacy_system_tag_aliases',
      where: 'system_tag_id = ?', whereArgs: [tag.id])).single;
    final canonicalId = alias['tag_id'] as int;
    await db.insert('task_tags', {
      'task_id': taskId, 'tag_id': canonicalId,
    });
    await db.insert('habit_tags', {
      'habit_id': habitId, 'tag_id': canonicalId,
    });
    final usage = await repo.getDeletionImpact(tag);
    expect(usage?.tasks, 1);
    expect(usage?.habits, 1);
    final undo = await repo.deleteWithUndo(tag, expectedImpact: usage!);
    expect(await db.query('system_tags', where: 'id = ?',
      whereArgs: [tag.id]), isEmpty);
    expect(await db.query('tags', where: 'id = ?',
      whereArgs: [canonicalId]), isEmpty);
    expect(await db.query('task_tags', where: 'task_id = ?',
      whereArgs: [taskId]), isEmpty);
    await undo.restore();
    expect(await db.query('system_tags', where: 'id = ?',
      whereArgs: [tag.id]), hasLength(1));
    expect(await db.query('tags', where: 'id = ?',
      whereArgs: [canonicalId]), hasLength(1));
    expect(await db.query('legacy_system_tag_aliases',
      where: 'system_tag_id = ?', whereArgs: [tag.id]), hasLength(1));
    expect(await db.query('task_tags', where: 'task_id = ?',
      whereArgs: [taskId]), hasLength(1));
    expect(await db.query('habit_tags', where: 'habit_id = ?',
      whereArgs: [habitId]), hasLength(1));
    expect((await db.query('tasks', where: 'id = ?',
      whereArgs: [taskId])).single['system_tag_id'], tag.id);
    expect((await db.query('habits', where: 'id = ?',
      whereArgs: [habitId])).single['system_tag_id'], tag.id);
    await expectLater(undo.restore(), throwsStateError);
  });

  test('X08 标签删除后任务被重新分配，不得按旧撤销覆盖新归属', () async {
    final repo = ObservationTagRepository();
    final oldTag = await repo.create(
      name: '旧标签', icon: '📚', color: '#112233',
    );
    final replacement = await repo.create(
      name: '新标签', icon: '📖', color: '#224466',
    );
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '清单', 'created_at': now, 'updated_at': now,
    });
    final taskId = await db.insert('tasks', {
      'list_id': listId, 'title': '重新分配',
      'system_tag_id': oldTag.id, 'created_at': now, 'updated_at': now,
    });
    final usage = await repo.getDeletionImpact(oldTag);
    final undo = await repo.deleteWithUndo(oldTag, expectedImpact: usage!);
    await db.update('tasks', {'system_tag_id': replacement.id},
      where: 'id = ?', whereArgs: [taskId]);
    await expectLater(undo.restore(), throwsStateError);
    expect((await db.query('tasks', where: 'id = ?',
      whereArgs: [taskId])).single['system_tag_id'], replacement.id);
    expect(await db.query('system_tags', where: 'id = ?',
      whereArgs: [oldTag.id]), isEmpty);
  });

  test('P15 本地标签关联仅计入存活任务且去重，旧专注关联删除后清空', () async {
    final repo = ObservationTagRepository();
    final tag = await repo.create(
      name: '专注观察', icon: '🎯', color: '#1890FF',
    );
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '本地清单', 'created_at': now, 'updated_at': now,
    });
    final taskId = await db.insert('tasks', {
      'list_id': listId, 'title': '实际任务',
      'system_tag_id': tag.id, 'created_at': now, 'updated_at': now,
    });
    final removed = await db.insert('tasks', {
      'list_id': listId, 'title': '已删除任务',
      'system_tag_id': tag.id, 'deleted_at': now,
      'created_at': now, 'updated_at': now,
    });
    final sessionId = await db.insert('work_sessions', {
      'session_type': 'work',
      'system_tag_id': tag.id,
      'started_at': now, 'created_at': now,
    });
    final usage = await repo.getAssociationUsage([tag]);
    expect(usage[tag.id]?.tasks, 1);
    expect(usage[tag.id]?.sessions, 1);
    expect(usage[tag.id]?.habits, 0);
    expect((await repo.getDeletionImpact(tag))?.tasks, 1);

    await repo.delete(tag);
    final tasks = await db.query('tasks', where: 'id IN (?, ?)',
        whereArgs: [taskId, removed]);
    expect(tasks.every((row) => row['system_tag_id'] == null), isTrue);
    final sessions = await db.query('work_sessions',
        where: 'id = ?', whereArgs: [sessionId]);
    expect(sessions.single['system_tag_id'], isNull);
    expect((await db.query('work_sessions', where: 'id = ?',
        whereArgs: [sessionId])), hasLength(1));
  });
}
