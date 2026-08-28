import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_behavior_event_schema.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/repositories/session_repository.dart';
import 'package:slowlight/services/data_mode_manager.dart';
import 'package:slowlight/services/data_service.dart';

import '../helpers/isolated_test_db.dart';

/// 本地数据模式集成测试。
///
/// 核心语义：本地模式以 SQLite 为数据源，不依赖 Slowlight 服务端，
/// 也不应把普通增删改查塞进等待服务端的 sync_queue。
void main() {
  late String dbPath;

  setUpAll(() async {
    dbPath = p.join(await useIsolatedTestDb('local_first'), 'slowlight_offline.db');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'data_mode': 'local'});
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
    LocalBehaviorEventSchema.resetForTest();
    await DataModeManager().setLocal();
  });

  tearDown(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
    LocalBehaviorEventSchema.resetForTest();
  });

  test('LocalDb v14 正式包含 work_sessions 与 ObservationTag 维度', () async {
    final db = await LocalDb().database;

    expect(await db.getVersion(), 14);
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='work_sessions'",
    );
    expect(tables, isNotEmpty);

    final columns = await db.rawQuery('PRAGMA table_info(work_sessions)');
    final names = columns.map((row) => row['name']).toSet();
    expect(
      names,
      containsAll(<String>{
        'id',
        'session_type',
        'task_id',
        'started_at',
        'ended_at',
        'duration_sec',
        'device',
        'system_tag_id',
      }),
    );

    final systemTagColumns = await db.rawQuery('PRAGMA table_info(system_tags)');
    final systemTagNames = systemTagColumns.map((row) => row['name']).toSet();
    expect(systemTagNames, contains('dimension_key'));
  });

  test('本地普通 CRUD 不进入 sync_queue', () async {
    final service = DataService();
    final list = await service.createList(name: '本地清单');

    final task = await service.createTask(
      listId: list.id,
      title: '本地任务',
      taskType: 'main',
      isMilestone: true,
      relatedQuestId: 42,
      obsidianLink: 'obsidian://slowlight/test',
      outputLevel: 'high',
    );

    expect(task.taskType, 'main');
    expect(task.isMilestone, isTrue);
    expect(task.relatedQuestId, 42);
    expect(task.obsidianLink, 'obsidian://slowlight/test');
    expect(task.outputLevel, 'high');

    final db = await LocalDb().database;
    final queue = await db.query('sync_queue');
    expect(queue, isEmpty);
  });

  test('本地 WorkSession 可开始、恢复、结束并统计', () async {
    final repo = SessionRepository();

    final started = await repo.startSession('work', device: 'test');
    expect(started['session']['session_type'], 'work');

    final active = await repo.getActiveSession();
    expect(active['active'], isTrue);
    expect(active['session']['device'], 'test');

    final ended = await repo.endSession(systemTagId: 7);
    expect(ended['session']['system_tag_id'], 7);
    expect(ended['session']['ended_at'], isNotNull);

    final activeAfterEnd = await repo.getActiveSession();
    expect(activeAfterEnd['active'], isFalse);

    final stats = await repo.getTodaySessionStats();
    expect(stats['work_count'], 1);
    expect(stats['break_count'], 0);
  });

  test('开始新 Session 会结束旧 Session，但只保留一个 active', () async {
    final repo = SessionRepository();

    await repo.startSession('work', device: 'test');
    await repo.startSession('break', device: 'test');

    final active = await repo.getActiveSession();
    expect(active['active'], isTrue);
    expect(active['session']['session_type'], 'break');

    final db = await LocalDb().database;
    final rows = await db.query('work_sessions', orderBy: 'id ASC');
    expect(rows.length, 2);
    expect(rows.first['ended_at'], isNotNull);
    expect(rows.last['ended_at'], isNull);
  });

  test('clearAll 会清理本地 WorkSession', () async {
    final repo = SessionRepository();
    await repo.startSession('work');

    await LocalDb().clearAll();

    final db = await LocalDb().database;
    final sessions = await db.query('work_sessions');
    expect(sessions, isEmpty);
  });
}