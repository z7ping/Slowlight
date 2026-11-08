import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/cloud_cache_db.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/repositories/cloud_cache_repository.dart';
import 'package:slowlight/repositories/habit_repository.dart';
import 'package:slowlight/repositories/local_habit_repository.dart';
import 'package:slowlight/services/data_mode_manager.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  setUpAll(() async => useIsolatedTestDb('p09_habit_note_search'));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DataModeManager().resetForTesting();
    await LocalDb().close();
    await CloudCacheDb().close();
    await databaseFactory.deleteDatabase(LocalDb.debugDatabasePathOverride!);
  });
  tearDown(() async {
    await LocalDb().close();
    await CloudCacheDb().close();
  });

  test('P09 Local notes search old records without per-habit API requests', () async {
    await DataModeManager().setLocal();
    final local = LocalHabitRepository();
    final a = await local.create(name: '阅读');
    final b = await local.create(name: '运动');
    final db = await LocalDb().database;
    for (final record in [
      (id: a['id'] as int, note: '摘录 100% 周报素材'),
      (id: b['id'] as int, note: '完成力量训练'),
    ]) {
      await db.insert('habit_logs', {
        'habit_id': record.id,
        'date': '2024-01-01',
        'note': record.note,
        'created_at': '2024-01-01T12:00:00Z',
      });
    }
    final hit = await HabitRepository().searchContent('100%');
    expect(hit.complete, isTrue);
    expect(hit.habits.map((e) => e.id), [a['id']]);
    expect(hit.habits.single.searchNote, contains('100%'));
    expect(hit.habits.single.searchNoteAt, isNotNull);
    expect((await HabitRepository().searchContent('100x')).habits, isEmpty);
    expect((await HabitRepository().searchContent('运动')).habits.single.id, b['id']);
    await local.delete(a['id'] as int);
    expect((await HabitRepository().searchContent('100%')).habits, isEmpty);
  });

  test('P09 Cloud cache notes are scoped to user and pending results survive', () async {
    const userId = 8721;
    SharedPreferences.setMockInitialValues({
      'user_data': jsonEncode({
        'id': userId,
        'username': 'p09_test',
        'email': 'p09@example.com',
      }),
    });
    await DataModeManager().setCloud();
    final db = await CloudCacheDb().database;
    final habitId = await db.insert('habits', {
      'server_id': 501,
      'name': '阅读',
      'created_at': '2024-01-01T00:00:00Z',
      'updated_at': '2024-01-01T00:00:00Z',
    });
    await db.insert('habit_logs', {
      'habit_id': habitId,
      'date': '2024-01-01',
      'note': 'a_b 周报素材',
      'sync_status': 'pending',
      'created_at': '2024-01-01T12:00:00Z',
    });
    final cache = CloudCacheRepository();
    final results = await cache.getHabits(search: 'a_b', pendingOnly: true);
    expect(results, hasLength(1));
    expect(results.single['id'], 501);
    expect(results.single['search_note'], contains('a_b'));
    expect((await cache.getHabits(search: 'axb')), isEmpty);
    await db.update('habit_logs', {'sync_status': 'synced'});
    expect(await cache.getHabits(search: 'a_b', pendingOnly: true), isEmpty);
    expect(await cache.getHabits(search: 'a_b'), hasLength(1));
  });
}
