import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/models/habit_log.dart';

void main() {
  test('旧习惯不通过名称或时长猜测记录类型', () {
    final habit = Habit.fromJson({
      'id': 1, 'user_id': 1, 'name': '早起',
      'duration_min': 30,
      'created_at': '2026-10-22T00:00:00Z',
    });
    expect(habit.recordType, 'legacy');
    expect(habit.recordTimeLabel, '');
  });

  test('新记录类型和配置由持久化字段决定', () {
    final habit = Habit.fromJson({
      'id': 2, 'user_id': 1, 'name': '任意名称',
      'record_type': 'count',
      'record_unit': '杯',
      'record_time_label': '完成时间',
      'created_at': '2026-10-22T00:00:00Z',
    });
    expect(habit.recordType, 'count');
    expect(habit.recordUnit, '杯');
    expect(habit.recordTimeLabel, '完成时间');
  });

  test('旧日志可以没有次数与实际发生时间', () {
    final log = HabitLog.fromJson({
      'id': 1, 'habit_id': 2, 'date': '2026-10-22',
      'duration_min': 20, 'created_at': '2026-10-22T01:00:00Z',
    });
    expect(log.countValue, isNull);
    expect(log.occurredAt, isNull);
  });

  test('计数和实际发生时间正确解析', () {
    final log = HabitLog.fromJson({
      'id': 2, 'habit_id': 2, 'date': '2026-10-22',
      'count_value': 12, 'duration_min': 0,
      'occurred_at': '2026-10-22T06:00:00Z',
      'created_at': '2026-10-22T06:00:00Z',
    });
    expect(log.countValue, 12);
    expect(log.durationMin, 0);
    expect(log.occurredAt?.toUtc().hour, 6);
  });
}
