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
