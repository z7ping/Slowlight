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
