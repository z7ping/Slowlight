import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit_goal_progress.dart';

void main() {
  final habit = <String, dynamic>{
    'goal_period': 'day',
    'goal_metric': 'count',
    'goal_value': 8,
  };
  final at = DateTime(2026, 10, 23, 15);
  test('同一天多条日志按数量累计，不按日志条数累计', () {
    final rows = [
      {'date': '2026-10-23', 'count_value': 1},
      {'date': '2026-10-23', 'count_value': 2},
      {'date': '2026-10-22', 'count_value': 100},
    ];
    final sum = HabitGoalProgress.current(habit, rows, now: at);
    expect(sum, 3);
    expect(HabitGoalProgress.met(habit, sum), false);
    expect(HabitGoalProgress.met(habit, 8), true);
  });

  test('事件数与分钟数的累计口径独立', () {
    final rows = [
      {'date': '2026-10-23', 'duration_min': 10, 'count_value': 3},
      {'date': '2026-10-23', 'duration_min': 20, 'count_value': 2},
    ];
    expect(HabitGoalProgress.current(
      {...habit, 'goal_metric': 'events'}, rows, now: at), 2);
    expect(HabitGoalProgress.current(
      {...habit, 'goal_metric': 'duration'}, rows, now: at), 30);
  });

  test('月目标跨周累计，周目标从周一开始', () {
    final rows = [
      {'date': '2026-10-01', 'count_value': 5},
      {'date': '2026-10-19', 'count_value': 2},
      {'date': '2026-10-23', 'count_value': 1},
    ];
    expect(HabitGoalProgress.current(
      {...habit, 'goal_period': 'week'}, rows, now: at), 3);
    expect(HabitGoalProgress.current(
      {...habit, 'goal_period': 'month'}, rows, now: at), 8);
  });
}
