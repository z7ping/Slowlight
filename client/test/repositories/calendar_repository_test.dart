import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/calendar_record.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/models/habit_log.dart';
import 'package:slowlight/models/reflection_entry.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/repositories/calendar_repository.dart';
import 'package:slowlight/repositories/habit_repository.dart';
import 'package:slowlight/repositories/reflection_repository.dart';
import 'package:slowlight/repositories/session_repository.dart';

class _TwoHabits extends HabitRepository {
  @override
  Future<List<Habit>> getAll() async => [
    for (final id in [1, 2])
      Habit(
        id: id,
        userId: 1,
        name: id == 1 ? '阅读' : '运动',
        icon: '📚',
        color: '#1890ff',
        frequency: 'daily',
        checkedToday: false,
        createdAt: DateTime(2026, 8, 1),
      ),
  ];

  @override
  Future<List<HabitLog>> logs(int habitId, {String? month}) async {
    if (habitId == 2) throw StateError('运动日志暂时不可用');
    return [
      HabitLog(
        id: 101,
        habitId: 1,
        date: '2026-08-21',
        period: 'morning',
        durationMin: 20,
        note: '真实已读取',
        createdAt: DateTime(2026, 8, 21),
      ),
    ];
  }
}

class _NoReflections extends ReflectionRepository {
  @override
  Future<({List<ReflectionEntry> entries, bool complete})> month(
          DateTime month) async =>
      (entries: const <ReflectionEntry>[], complete: true);
}

class _NoHabits extends HabitRepository {
  @override
  Future<List<Habit>> getAll() async => const [];
}

class _SampleHabit extends HabitRepository {
  @override
  Future<List<Habit>> getAll() async => [
        Habit(
          id: 5, userId: 1, name: '阅读', specificTime: '08:00',
          durationMin: 45, recordUnit: '页',
          createdAt: DateTime(2026, 8, 1),
        ),
      ];

  @override
  Future<List<HabitLog>> logs(int habitId, {String? month}) async => [
        HabitLog(
          id: 6, habitId: habitId, date: '2026-08-21',
          period: 'morning', durationMin: 0,
          countValue: 2, occurredAt: DateTime(2026, 8, 21, 9, 35),
          note: '真实记录', createdAt: DateTime(2026, 8, 21, 10),
        ),
      ];
}

class _BadFocus extends SessionRepository {
  @override
  Future<Map<String, dynamic>> getSessionStats({String period = 'week'}) async =>
      {'total_work_seconds': 2700, 'work_count': 1};
}

class _MonthReflections extends ReflectionRepository {
  @override
  Future<({List<ReflectionEntry> entries, bool complete})> month(
          DateTime month) async => (
        complete: false,
        entries: [
          for (var id = 1; id <= 120; id++)
            ReflectionEntry(
              id: id, entryType: 'observation', content: '观察 #$id',
              createdAt: DateTime(2026, 8, 21, 14),
            ),
        ],
      );
}

class _NoSessions extends SessionRepository {
  @override
  Future<Map<String, dynamic>> getSessionStats({String period = 'week'}) async =>
      {'daily': <Map<String, dynamic>>[]};
}

void main() {
  test('F-001 云端纯日期在月初跨 UTC 日界仍归属选中日及正确月份', () async {
    final task = Task.fromJson({
      'id': 275, 'list_id': 1, 'title': '月初计划',
      'priority': 'none', 'is_completed': false,
      'due_date': '2026-10-31T16:00:00Z',
      'created_at': '2026-10-31T12:00:00Z',
    });
    final repo = CalendarRepository(
      habitRepository: _NoHabits(),
      reflectionRepository: _NoReflections(),
      sessionRepository: _NoSessions(),
      taskLoader: (_, __) async => [task],
    );
    final november = await repo.loadMonth(DateTime(2026, 11));
    final plan = november.records.singleWhere((r) => r.id == 'task-275-plan');
    expect(plan.kind, CalendarRecordKind.plan);
    expect(plan.date, DateTime(2026, 11, 1));
    final october = await repo.loadMonth(DateTime(2026, 10));
    expect(october.records.where((r) => r.id == 'task-275-plan'), isEmpty);
  });

  test('P08 截止日期不当成真实完成日期；跨月和无截止完成仍可见', () async {
    final completed = [
      Task(
        id: 31, listId: 1, title: '先计划后完成',
        priority: 'high', dueDate: DateTime(2026, 8, 4),
        isCompleted: true, completedAt: DateTime(2026, 8, 7, 18, 20),
        createdAt: DateTime(2026, 7),
      ),
      Task(
        id: 32, listId: 1, title: '无截止但已完成',
        priority: 'none', isCompleted: true,
        completedAt: DateTime(2026, 8, 9, 7),
        createdAt: DateTime(2026, 8),
      ),
      Task(
        id: 33, listId: 1, title: '当天计划与完成',
        priority: 'none', dueDate: DateTime(2026, 8, 10),
        isCompleted: true, completedAt: DateTime(2026, 8, 10, 16),
        createdAt: DateTime(2026, 8),
      ),
    ];
    final repo = CalendarRepository(
      habitRepository: _NoHabits(), reflectionRepository: _NoReflections(),
      sessionRepository: _NoSessions(),
      taskLoader: (_, __) async => [completed[0], completed[2]],
      completedTaskLoader: () async => completed,
    );
    final data = await repo.loadMonth(DateTime(2026, 8));
    final tasks = data.records.where((r) => r.type == CalendarRecordType.task);
    expect(tasks, hasLength(4));
    final planned = tasks.singleWhere((r) => r.id == 'task-31-plan');
    expect(planned.kind, CalendarRecordKind.plan);
    expect(planned.date.day, 4);
    expect(planned.completed, false);
    final actual = tasks.singleWhere((r) => r.id == 'task-31-actual');
    expect(actual.kind, CalendarRecordKind.actual);
    expect(actual.date.day, 7);
    expect(actual.completed, true);
    expect(actual.timeLabel, '18:20 完成');
    expect(tasks.singleWhere((r) => r.id == 'task-32-actual').date.day, 9);
    expect(tasks.where((r) => r.id.startsWith('task-33-')),
        hasLength(1));
    expect(data.unavailableTypes, isEmpty);
  });

  test('P08 习惯事实不借用计划时刻、目标时长或数量', () async {
    final repo = CalendarRepository(
      habitRepository: _SampleHabit(),
      reflectionRepository: _NoReflections(),
      sessionRepository: _NoSessions(),
      taskLoader: (_, __) async => [],
    );
    final data = await repo.loadMonth(DateTime(2026, 8));
    final record = data.records.single;
    expect(record.type, CalendarRecordType.habit);
    expect(record.timeLabel, '09:35');
    expect(record.durationMin, 0);
    expect(record.amountLabel, '2 页');
    expect(record.description, '真实记录');
  });

  test('P08 专注汇总缺日记录不能当作确认无活动', () async {
    final repo = CalendarRepository(
      habitRepository: _NoHabits(), reflectionRepository: _NoReflections(),
      sessionRepository: _BadFocus(),
      taskLoader: (_, __) async => [],
    );
    final data = await repo.loadMonth(DateTime(2026, 8));
    expect(data.unavailableTypes, contains(CalendarRecordType.focus));
    expect(data.unavailableTypes, isNot(contains(CalendarRecordType.task)));
  });

  test('P08 观察缓存有 120 条时保留事实并标记未完整', () async {
    final repo = CalendarRepository(
      habitRepository: _NoHabits(),
      reflectionRepository: _MonthReflections(),
      sessionRepository: _NoSessions(),
      taskLoader: (_, __) async => [],
    );
    final data = await repo.loadMonth(DateTime(2026, 8));
    expect(data.records.where(
        (r) => r.type == CalendarRecordType.reflection), hasLength(120));
    expect(data.unavailableTypes, contains(CalendarRecordType.reflection));
  });


  test('P08 某一习惯的月日志失败不清空其他已确认日历记录', () async {
    final repository = CalendarRepository(
      habitRepository: _TwoHabits(),
      reflectionRepository: _NoReflections(),
      sessionRepository: _NoSessions(),
      taskLoader: (year, month) async => <Task>[],
    );
    final month = await repository.loadMonth(DateTime(2026, 8));
    final habitRecords = month.records.where(
      (record) => record.type == CalendarRecordType.habit,
    );
    expect(habitRecords, hasLength(1));
    expect(habitRecords.single.title, '📚 阅读');
    expect(habitRecords.single.description, '真实已读取');
    expect(month.unavailableTypes, contains(CalendarRecordType.habit));
    expect(month.unavailableTypes, isNot(contains(CalendarRecordType.task)));
  });
}
