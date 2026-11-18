import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/repositories/habit_repository.dart';
import 'package:slowlight/services/data_source.dart';

class FakeHabitDataSource implements ApiDataSource {
  final List<Map<String, dynamic>> habits = [
    {
      'id': 1,
      'user_id': 1,
      'name': '阅读',
      'icon': '📚',
      'color': '#1890ff',
      'frequency': 'daily',
      'target_days': 30,
      'streak_count': 2,
      'preferred_period': 'evening',
      'system_tag_id': 9,
      'generate_task': true,
      'show_checkin_dialog': true,
      'duration_min': 20,
      'specific_time': '21:30',
      'reminder_at': {
        'enabled': true,
        'hour': 21,
        'minute': 20,
      },
      'checked_today': true,
      'checked_days': ['2026-08-20', '2026-08-21'],
      'created_at': '2026-08-01T00:00:00Z',
    },
  ];

  Map<String, dynamic>? lastCreate;
  Map<String, dynamic>? lastUpdate;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<Map<String, dynamic>>> getHabits() async =>
      habits.map(Map<String, dynamic>.from).toList();

  @override
  Future<Map<String, dynamic>> createHabit({
    required String name,
    String icon = '✅',
    String color = '#52c41a',
    String frequency = 'daily',
    Map<String,dynamic>? scheduleRule,
    String recordType = 'check',
    String recordUnit = '次',
    String recordTimeLabel = '',
    bool allowMultiplePerDay = false,
    String goalPeriod = 'none',
    String goalMetric = 'events',
    int goalValue = 0,
    int targetDays = 0,
    int? systemTagId,
    String preferredPeriod = '',
    int durationMin = 0,
    bool generateTask = false,
    bool showCheckinDialog = false,
    String specificTime = '',
    Map<String, dynamic>? reminderAt,
  }) async {
    final value = <String, dynamic>{
      'id': 2,
      'user_id': 1,
      'name': name,
      'icon': icon,
      'color': color,
      'frequency': frequency,
      'record_type':recordType,
      'record_unit':recordUnit,
      'record_time_label':recordTimeLabel,
      'allow_multiple_per_day': allowMultiplePerDay,
      'goal_period': goalPeriod,
      'goal_metric': goalMetric,
      'goal_value': goalValue,
      'schedule_rule': scheduleRule ?? const <String, dynamic>{},
      'target_days': targetDays,
      'streak_count': 0,
      'preferred_period': preferredPeriod,
      'system_tag_id': systemTagId,
      'generate_task': generateTask,
      'show_checkin_dialog': showCheckinDialog,
      'duration_min': durationMin,
      'specific_time': specificTime,
      'reminder_at': reminderAt ?? const <String, dynamic>{},
      'checked_today': false,
      'checked_days': const <String>[],
      'created_at': '2026-08-21T00:00:00Z',
    };
    lastCreate = Map<String, dynamic>.from(value);
    habits.add(value);
    return Map<String, dynamic>.from(value);
  }

  @override
  Future<void> updateHabit(int habitId, Map<String, dynamic> data) async {
    lastUpdate = Map<String, dynamic>.from(data);
    final index = habits.indexWhere((item) => item['id'] == habitId);
    if (index < 0) throw StateError('habit not found');
    habits[index] = {
      ...habits[index],
      ...data,
    };
  }
}

void main() {
  test('getAll exposes checked state and habit schedule fields as strong types', () async {
    final source = FakeHabitDataSource();
    final repo = HabitRepository(dataSource: source);

    final habit = (await repo.getAll()).single;

    expect(habit.checkedToday, isTrue);
    expect(habit.checkedDays, contains('2026-08-21'));
    expect(habit.preferredPeriod, 'evening');
    expect(habit.specificTime, '21:30');
    expect(habit.reminderEnabled, isTrue);
    expect(habit.reminderAt['hour'], 21);
  });

  test('create keeps preferred period, exact time and reminder separate', () async {
    final source = FakeHabitDataSource();
    final repo = HabitRepository(dataSource: source);

    final created = await repo.create(
      name: '散步',
      preferredPeriod: 'evening',
      specificTime: '19:30',
      reminderAt: const {
        'enabled': true,
        'hour': 19,
        'minute': 20,
      },
    );

    expect(created.recordType, 'check');
    expect(created.preferredPeriod, 'evening');
    expect(created.specificTime, '19:30');
    expect(source.lastCreate?['reminder_at']['enabled'], isTrue);
  });

  test('update can explicitly clear observation tag and preserve false values', () async {
    final source = FakeHabitDataSource();
    final repo = HabitRepository(dataSource: source);
    final Habit habit = (await repo.getAll()).single;

    final updated = await repo.update(
      habit,
      systemTagId: null,
      updateSystemTag: true,
      generateTask: false,
      showCheckinDialog: false,
      durationMin: 0,
      specificTime: '',
      reminderAt: const {'enabled': false},
    );

    expect(source.lastUpdate?['system_tag_id'], isNull);
    expect(source.lastUpdate?['generate_task'], isFalse);
    expect(source.lastUpdate?['show_checkin_dialog'], isFalse);
    expect(source.lastUpdate?['duration_min'], 0);
    expect(updated.systemTagId, isNull);
    expect(updated.specificTime, '');
  });

  test('update only sends changed legacy scheduling fields', () async {
    final source = FakeHabitDataSource();
    source.habits.single['schedule_rule'] = const <String, dynamic>{};
    final repo = HabitRepository(dataSource: source);
    final habit = (await repo.getAll()).single;

    final renamed = await repo.update(
      habit,
      name: '晚间阅读',
      frequency: habit.frequency,
      scheduleRule: const {},
    );
    expect(source.lastUpdate, isNot(contains('schedule_rule')));
    expect(source.lastUpdate, isNot(contains('frequency')));
    expect(renamed.name, '晚间阅读');
    expect(renamed.scheduleRule, isEmpty);
    expect(renamed.frequency, habit.frequency);

    final rescheduled = await repo.update(renamed, frequency: 'weekly');
    expect(source.lastUpdate, isNot(contains('schedule_rule')));
    expect(rescheduled.frequency, 'weekly');

    const rule = {'version': 1, 'kind': 'interval', 'anchor_date': '2026-08-01'};
    await repo.update(rescheduled, scheduleRule: rule);
    expect(source.lastUpdate?['schedule_rule'], rule);
  });
}
