import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/repositories/local_list_repository.dart';
import 'package:slowlight/services/local_api_service.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  late String dbPath;

  setUpAll(() async {
    dbPath = p.join(
      await useIsolatedTestDb('local_list_repository'),
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

  test('缺失收集箱时补齐一次并保留原有清单', () async {
    final repo = LocalListRepository();
    final work = await repo.create(name: '工作', icon: '💼');
    final inbox = await repo.ensureInbox();
    final repeated = await repo.ensureInbox();

    expect(inbox.isInbox, isTrue);
    expect(inbox.name, '收集箱');
    expect(inbox.id, repeated.id);
    final lists = await repo.getAll();
    expect(lists, hasLength(2));
    expect(lists.first.id, inbox.id);
    expect(lists.last.id, work.id);
    expect(lists.last.name, '工作');
  });

  test('已有收集箱不被重建或覆盖名称', () async {
    final repo = LocalListRepository();
    final customized = await repo.create(
      name: '我的收集箱',
      icon: '🗃',
      isInbox: true,
    );
    final inbox = await repo.ensureInbox();
    expect(inbox.id, customized.id);
    expect(inbox.name, '我的收集箱');
    expect(await repo.getAll(), hasLength(1));
  });

  test('快速添加始终进入真正的收集箱，不误用第一个清单', () async {
    final repo = LocalListRepository();
    await repo.create(name: '工作');
    final task = await LocalApiService().quickAddToInbox('记录想法');
    final inbox = (await repo.getAll()).singleWhere((list) => list.isInbox);
    expect(task.listId, inbox.id);
    expect(task.title, '记录想法');
    final repeated = await LocalApiService().quickAddToInbox('第二条');
    expect(repeated.listId, inbox.id);
    expect((await repo.getAll()).where((list) => list.isInbox), hasLength(1));
  });
  test('P14 删除清单将本清单未完成/已完成任务一起软删除，其他清单不受影响', () async {
    final repo = LocalListRepository();
    final work = await repo.create(name: '项目');
    final other = await repo.create(name: '其他');
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    Future<int> put(int listId, String name, {bool done = false}) =>
        db.insert('tasks', {
          'list_id': listId,
          'title': name,
          'is_completed': done ? 1 : 0,
          'created_at': now,
          'updated_at': now,
        });
    final one = await put(work.id, '未完成任务');
    final two = await put(work.id, '已完成任务', done: true);
    final safe = await put(other.id, '其他清单任务');

    await repo.delete(work.id, deleteTasks: true);
    final lists = await repo.getAll();
    expect(lists.map((list) => list.id), isNot(contains(work.id)));
    expect(lists.map((list) => list.id), contains(other.id));
    for (final id in [one, two]) {
      final rows = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
      expect(rows.single['deleted_at'], isNotNull);
    }
    final otherRows = await db.query('tasks', where: 'id = ?', whereArgs: [safe]);
    expect(otherRows.single['deleted_at'], isNull);
  });

  test('X08 撤销清单删除恢复原任务ID，不复活此前已删除任务', () async {
    final repo = LocalListRepository();
    final list = await repo.create(name: '原始清单');
    final other = await repo.create(name: '其他清单');
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    Future<int> insert(int listId, String title, {String? deletedAt}) =>
        db.insert('tasks', {
          'list_id': listId, 'title': title,
          'created_at': now, 'updated_at': now,
          'deleted_at': deletedAt,
        });
    final one = await insert(list.id, '任务一');
    final two = await insert(list.id, '任务二');
    final previouslyDeleted = await insert(list.id, '历史删除',
      deletedAt: now);
    final unrelated = await insert(other.id, '未受影响');
    final receipt = await repo.deleteWithUndo(list.id, expectedTaskCount: 2);
    expect(await repo.getById(list.id), isNull);
    await repo.undoDelete(receipt);
    expect(await repo.getById(list.id), isNotNull);
    for (final id in [one, two, unrelated]) {
      expect((await db.query('tasks', where: 'id = ?',
        whereArgs: [id])).single['deleted_at'], isNull);
    }
    expect((await db.query('tasks', where: 'id = ?',
      whereArgs: [previouslyDeleted])).single['deleted_at'], now);
    await expectLater(repo.undoDelete(receipt), throwsStateError);
  });

  test('X08 任务墓碑被其他写入改变时撤销必须整体回滚', () async {
    final repo = LocalListRepository();
    final list = await repo.create(name: '禁止部分还原');
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final taskId = await db.insert('tasks', {
      'list_id': list.id, 'title': '原任务',
      'created_at': now, 'updated_at': now,
    });
    final receipt = await repo.deleteWithUndo(list.id,
      expectedTaskCount: 1);
    await db.update('tasks',
      {'deleted_at': '2020-01-01T00:00:00Z'},
      where: 'id = ?', whereArgs: [taskId]);
    await expectLater(repo.undoDelete(receipt), throwsStateError);
    expect(await repo.getById(list.id), isNull);
  });

  test('X08 任务范围变化后禁止按旧确认删除清单', () async {
    final repo = LocalListRepository();
    final list = await repo.create(name: '待核对');
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final taskId = await db.insert('tasks', {
      'list_id': list.id,
      'title': '确认后新增',
      'created_at': now,
      'updated_at': now,
    });
    await expectLater(
      repo.delete(list.id, deleteTasks: true, expectedTaskCount: 0),
      throwsStateError,
    );
    expect(await repo.getById(list.id), isNotNull);
    expect((await db.query('tasks', where: 'id = ?',
      whereArgs: [taskId])).single['deleted_at'], isNull);
    await repo.delete(list.id, deleteTasks: true, expectedTaskCount: 1);
    expect(await repo.getById(list.id), isNull);
  });

  test('P14 默认收集箱不能删除，关联任务原样保留', () async {
    final repo = LocalListRepository();
    final inbox = await repo.ensureInbox();
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final taskId = await db.insert('tasks', {
      'list_id': inbox.id,
      'title': '收集箱任务',
      'created_at': now,
      'updated_at': now,
    });
    await expectLater(repo.delete(inbox.id), throwsStateError);
    expect((await repo.getAll()).single.id, inbox.id);
    final rows = await db.query('tasks', where: 'id = ?', whereArgs: [taskId]);
    expect(rows.single['deleted_at'], isNull);
  });

  test('P14 普通删除有任务的清单必须拒绝，无副作用', () async {
    final repo = LocalListRepository();
    final list = await repo.create(name: '旧客户端清单');
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final taskId = await db.insert('tasks', {
      'list_id': list.id,
      'title': '不该误删',
      'created_at': now,
      'updated_at': now,
    });
    await expectLater(repo.delete(list.id), throwsStateError);
    expect((await repo.getAll()).single.id, list.id);
    expect((await db.query('tasks', where: 'id = ?', whereArgs: [taskId]))
        .single['deleted_at'], isNull);
  });

}
