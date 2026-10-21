import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/repositories/local_session_repository.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  final localDb = LocalDb();
  final repository = LocalSessionRepository();
  late String dbPath;

  Future<void> resetDatabase() async {
    await localDb.close();
    await databaseFactory.deleteDatabase(dbPath);
  }

  setUpAll(() async {
    dbPath = p.join(await useIsolatedTestDb('session_repository'), 'slowlight_offline.db');
  });

  setUp(resetDatabase);
  tearDown(resetDatabase);

  test('startSession creates a local active session with server-compatible keys',
      () async {
    final started = await repository.startSession('work');
    final session = started['session'] as Map<String, dynamic>;

    expect(session['session_type'], 'work');
    expect(session['duration_seconds'], 0);
    expect(session.containsKey('duration_sec'), isFalse);

    final active = await repository.getActiveSession();
    expect(active['active'], isTrue);
    expect((active['config'] as Map<String, dynamic>)['sessions_before_long'], 4);
  });

  test('starting another session automatically ends the previous session',
      () async {
    final first = await repository.startSession('work');
    final firstId = (first['session'] as Map<String, dynamic>)['id'] as int;

    await repository.startSession('break');

    final db = await localDb.database;
    final oldRows = await db.query(
      'work_sessions',
      where: 'id = ?',
      whereArgs: [firstId],
      limit: 1,
    );
    expect(oldRows.single['ended_at'], isNotNull);

    final active = await repository.getActiveSession();
    expect(active['active'], isTrue);
    expect(
      (active['session'] as Map<String, dynamic>)['session_type'],
      'break',
    );
  });

  test('pause/resume is idempotent and excludes paused seconds from stats',
      () async {
    final started = await repository.startSession('work');
    final id = (started['session'] as Map<String, dynamic>)['id'] as int;
    final db = await localDb.database;
    final now = DateTime.now().toUtc();
    await db.update('work_sessions', {
      'started_at': now.subtract(const Duration(minutes: 15)).toIso8601String(),
      'paused_at': now.subtract(const Duration(minutes: 2)).toIso8601String(),
      'paused_duration_sec': 300,
      'revision': 1,
    }, where: 'id = ?', whereArgs: [id]);

    final paused = await repository.pauseSession(id, 0);
    final pauseDate = (paused['session'] as Map)['paused_at'];
    expect(pauseDate, isNotNull);
    final repeated = await repository.pauseSession(id, 0);
    expect((repeated['session'] as Map)['paused_at'], pauseDate);

    final resumed = await repository.resumeSession(id, 1);
    expect((resumed['session'] as Map)['paused_at'], isNull);
    final repeatedResume = await repository.resumeSession(id, 1);
    expect((repeatedResume['session'] as Map)['paused_duration_seconds'],
        (resumed['session'] as Map)['paused_duration_seconds']);

    await expectLater(repository.pauseSession(id, 0), throwsStateError);
    final ended = await repository.endSession();
    final seconds = ended['duration'] as int;
    expect(seconds, inInclusiveRange(470, 490));
    final stats = await repository.getTodaySessionStats();
    expect(stats['total_work_seconds'], seconds);
    await expectLater(repository.pauseSession(id, 0), throwsStateError);
  });

  test('database v15 upgrades existing work sessions without deleting history',
      () async {
    await resetDatabase();
    final legacy = await openDatabase(dbPath, version: 15, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE work_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_type TEXT NOT NULL, task_id INTEGER,
          started_at TEXT NOT NULL, ended_at TEXT,
          duration_sec INTEGER DEFAULT 0, device TEXT DEFAULT '',
          system_tag_id INTEGER, created_at TEXT NOT NULL
        )
      ''');
      await db.insert('work_sessions', {
        'session_type': 'work',
        'started_at': '2026-01-01T00:00:00Z',
        'duration_sec': 60,
        'created_at': '2026-01-01T00:00:00Z',
      });
    });
    await legacy.close();

    final upgraded = await localDb.database;
    final rows = await upgraded.query('work_sessions');
    expect(rows, hasLength(1));
    expect(rows.single['duration_sec'], 60);
    expect(rows.single['paused_duration_sec'], 0);
    expect(rows.single['revision'], 0);
    expect(rows.single['paused_at'], isNull);
  });

  test('endSession inherits system tag from related task before explicit tag',
      () async {
    final db = await localDb.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '测试清单',
      'icon': '📋',
      'color': '#1890ff',
      'created_at': now,
      'updated_at': now,
    });
    final taskId = await db.insert('tasks', {
      'list_id': listId,
      'title': '测试任务',
      'system_tag_id': 7,
      'created_at': now,
      'updated_at': now,
    });

    await repository.startSession('work', taskId: taskId);
    final ended = await repository.endSession(systemTagId: 9);
    final session = ended['session'] as Map<String, dynamic>;

    expect(session['system_tag_id'], 7);
    expect(session['duration_seconds'], isA<int>());

    final stats = await repository.getTodaySessionStats();
    expect(stats['work_count'], 1);
    expect(stats.containsKey('daily'), isTrue);
    expect(stats.containsKey('sessions'), isFalse);
  });
}
