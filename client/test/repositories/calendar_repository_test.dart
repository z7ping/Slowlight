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
  Future<List<ReflectionEntry>> recent({int limit = 20}) async => const [];
}

class _NoSessions extends SessionRepository {
  @override
  Future<Map<String, dynamic>> getSessionStats({String period = 'week'}) async =>
      {'daily': <Map<String, dynamic>>[]};
}

void main() {
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
