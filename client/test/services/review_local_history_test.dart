import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/services/review_local_service.dart';
import 'package:slowlight/utils/local_time_boundary.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => useIsolatedTestDb('p12_review_local_history'));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb().close();
    await databaseFactory.deleteDatabase(LocalDb.debugDatabasePathOverride!);
  });
  tearDown(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(LocalDb.debugDatabasePathOverride!);
  });

  test('P12 Local 历史任务返回完成自然日，软删除不参与统计', () async {
    final db = await LocalDb().database;
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1, 15, 20);
    final dateInstant = LocalTimeBoundary.instant(yesterday);
    final listId = await db.insert('lists', {
      'name': '工作',
      'created_at': dateInstant,
      'updated_at': dateInstant,
    });
    Future<void> addTask(String title, {bool deleted = false}) async {
      await db.insert('tasks', {
        'list_id': listId,
        'title': title,
        'is_completed': 1,
        'task_type': 'daily',
        'completed_at': dateInstant,
        'created_at': dateInstant,
        'updated_at': dateInstant,
        if (deleted) 'deleted_at': dateInstant,
      });
    }
    await addTask('真实完成');
    await addTask('已删除任务', deleted: true);

    final result = await ReviewLocalService().computeTasksReview(30);
    final summary = result['summary'] as Map<String, dynamic>;
    final tasks = result['completed_tasks'] as List<dynamic>;
    expect(summary['completed_count'], 1);
    expect(summary['created_count'], 1);
    expect(tasks, hasLength(1));
    final row = tasks.single as Map<String, dynamic>;
    expect(row['title'], '真实完成');
    expect(row['completed_date'], LocalTimeBoundary.dateKey(yesterday));
    expect(row['completed_at'], '15:20');
  });
}
