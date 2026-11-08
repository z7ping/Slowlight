import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/db/local_product_core_schema.dart';
import 'package:slowlight/repositories/local_task_repository.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  late String dbPath;

  setUpAll(() async {
    dbPath = p.join(
      await useIsolatedTestDb('task_postpone_tomorrow'),
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

  test('本地顺延撤销只恢复原日期；重复撤销不会覆盖新修改', () async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final now = DateTime.now();
    final listId = await db.insert('lists', {
      'name': '日常',
      'created_at': now.toUtc().toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
    });
    final repo = LocalTaskRepository();
    final originalDue = DateTime(now.year, now.month, now.day);
    final created = await repo.create(
      listId: listId, title: '不可覆盖标题',
      dueDate: originalDue, description: '保留原描述',
    );
    final postponed = await repo.postpone(created.id);
    final undone = await repo.restorePostponedDueDate(
      created.id,
      expectedDueDate: postponed.dueDate!,
      originalDueDate: created.dueDate,
    );
    expect(undone.dueDate?.day, originalDue.day);
    expect(undone.title, '不可覆盖标题');
    expect(undone.description, '保留原描述');
    await expectLater(
      () => repo.restorePostponedDueDate(
        created.id,
        expectedDueDate: postponed.dueDate!,
        originalDueDate: null,
      ),
      throwsStateError,
    );
    final reloaded = await repo.getById(created.id);
    expect(reloaded?.dueDate?.day, originalDue.day);
  });

  test('本地顺延真实指向明天，而不是仍落在今天', () async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final now = DateTime.now();
    final utc = now.toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '日常',
      'created_at': utc,
      'updated_at': utc,
    });
    final repo = LocalTaskRepository();
    final created = await repo.create(
      listId: listId,
      title: '阅读',
      dueDate: DateTime(now.year, now.month, now.day),
    );
    final postponed = await repo.postpone(created.id);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    expect(postponed.dueDate?.year, tomorrow.year);
    expect(postponed.dueDate?.month, tomorrow.month);
    expect(postponed.dueDate?.day, tomorrow.day);
    expect((await repo.getTodayTasks()).any((item) => item.id == created.id),
        isFalse);
  });
}
