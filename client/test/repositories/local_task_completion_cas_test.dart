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
      await useIsolatedTestDb('task_completion_cas'),
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

  test('X03 Local 完成/撤销遵守原状态及 completed_at 条件', () async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '任务',
      'created_at': now,
      'updated_at': now,
    });
    final repo = LocalTaskRepository();
    final created = await repo.create(
      listId: listId,
      title: 'CAS 完成任务',
    );
    final first = await repo.setTaskCompletion(
      created.id,
      completed: true,
      expectedCompleted: false,
    );
    expect(first.isCompleted, isTrue);
    expect(first.completedAt, isNotNull);
    await expectLater(
      repo.setTaskCompletion(
        created.id,
        completed: true,
        expectedCompleted: false,
      ),
      throwsStateError,
    );
    final undone = await repo.setTaskCompletion(
      created.id,
      completed: false,
      expectedCompleted: true,
      expectedCompletedAt: first.completedAt,
    );
    expect(undone.isCompleted, isFalse);
    expect(undone.completedAt, isNull);
    await expectLater(
      repo.setTaskCompletion(
        created.id,
        completed: false,
        expectedCompleted: true,
        expectedCompletedAt: first.completedAt,
      ),
      throwsStateError,
    );
    final next = await repo.setTaskCompletion(
      created.id,
      completed: true,
      expectedCompleted: false,
    );
    expect(next.isCompleted, isTrue);
    // The previous undo cannot apply to a new completion cycle even
    // if the two status values are both "completed".
    if (next.completedAt != null &&
        !next.completedAt!.isAtSameMomentAs(first.completedAt!)) {
      await expectLater(
        repo.setTaskCompletion(
          created.id,
          completed: false,
          expectedCompleted: true,
          expectedCompletedAt: first.completedAt,
        ),
        throwsStateError,
      );
    }
  });
}
