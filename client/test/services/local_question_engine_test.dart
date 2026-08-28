import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/services/local_question_engine.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  late String dbPath;
  final fixedNow = DateTime(2026, 8, 21, 21);

  setUpAll(() async {
    dbPath = p.join(
      await useIsolatedTestDb('question_engine'),
      'slowlight_offline.db',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
  });

  tearDown(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
  });

  Future<int> createList(Database db) => db.insert('lists', {
        'name': '默认',
        'created_at': fixedNow.subtract(const Duration(days: 30)).toIso8601String(),
        'updated_at': fixedNow.toIso8601String(),
      });

  test('最多返回两个问题，按规则优先级且 7 天内去重', () async {
    final db = await LocalDb().database;
    final listId = await createList(db);

    for (var i = 0; i < 3; i++) {
      await db.insert('tasks', {
        'list_id': listId,
        'title': '旧任务 $i',
        'created_at': fixedNow.subtract(const Duration(days: 10)).toIso8601String(),
        'updated_at': fixedNow.toIso8601String(),
      });
    }

    for (var i = 0; i < 6; i++) {
      await db.insert('tasks', {
        'list_id': listId,
        'title': '本周任务 $i',
        'created_at': DateTime(2026, 8, 17, 9 + i).toIso8601String(),
        'updated_at': fixedNow.toIso8601String(),
      });
    }

    final engine = LocalQuestionEngine(now: () => fixedNow);
    final first = await engine.generate(db);
    expect(first, hasLength(2));
    expect(first[0]['id'], 'task_backlog_7d');
    expect(first[0]['content'], contains('现在还重要吗'));
    expect(first[1]['id'], 'completion_rate_weekly');
    expect(first[1]['content'], contains('和你预期的一样吗'));

    final second = await engine.generate(db);
    expect(second.where((q) => q['id'] == 'task_backlog_7d'), isEmpty);
    expect(second.where((q) => q['id'] == 'completion_rate_weekly'), isEmpty);
  });

  test('新习惯问题只描述事实并提问，不直接给建议', () async {
    final db = await LocalDb().database;
    final created = fixedNow.subtract(const Duration(days: 5));
    final habitId = await db.insert('habits', {
      'name': '跑步',
      'created_at': created.toIso8601String(),
      'updated_at': fixedNow.toIso8601String(),
    });
    await db.insert('habit_logs', {
      'habit_id': habitId,
      'date': '2026-08-17',
      'created_at': DateTime(2026, 8, 17, 9).toIso8601String(),
    });

    final engine = LocalQuestionEngine(now: () => fixedNow);
    final questions = await engine.generate(db);
    final q = questions.firstWhere((item) => item['type'] == 'new_habit_struggle');

    expect(q['content'], contains('目前记录 1 次'));
    expect(q['content'], contains('是什么让你没有继续'));
    expect(q['content'], isNot(contains('降低难度')));
  });

  test('完成率只统计本周创建 cohort，旧任务本周完成不进入分子', () async {
    final db = await LocalDb().database;
    final listId = await createList(db);

    for (var i = 0; i < 6; i++) {
      final completed = i < 2;
      await db.insert('tasks', {
        'list_id': listId,
        'title': '本周 cohort $i',
        'created_at': DateTime(2026, 8, 17, 9 + i).toIso8601String(),
        'updated_at': fixedNow.toIso8601String(),
        'is_completed': completed ? 1 : 0,
        'completed_at': completed
            ? DateTime(2026, 8, 20, 9 + i).toIso8601String()
            : null,
      });
    }

    for (var i = 0; i < 4; i++) {
      await db.insert('tasks', {
        'list_id': listId,
        'title': '旧任务本周完成 $i',
        'created_at': DateTime(2026, 8, 10, 9 + i).toIso8601String(),
        'updated_at': fixedNow.toIso8601String(),
        'is_completed': 1,
        'completed_at': DateTime(2026, 8, 20, 14 + i).toIso8601String(),
      });
    }

    final questions = await LocalQuestionEngine(now: () => fixedNow).generate(db);
    final question =
        questions.firstWhere((q) => q['id'] == 'completion_rate_weekly');
    expect(question['content'], contains('本周创建了 6 个任务'));
    expect(question['content'], contains('其中 2 个目前已完成'));
    expect(question['content'], isNot(contains('完成了 6 个')));
  });
}
