/// 习惯记录进度：事件数、实际数量与时长不得混用。
abstract final class HabitGoalProgress {
  static String _dayKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  static int current(Map<String, dynamic> habit,
      Iterable<Map<String, dynamic>> logs, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final period = habit['goal_period'] as String? ?? 'none';
    final metric = habit['goal_metric'] as String? ?? 'events';
    DateTime first;
    switch (period) {
      case 'week':
        final start = DateTime(today.year, today.month, today.day);
        first = start.subtract(Duration(days: today.weekday - 1));
        break;
      case 'month':
        first = DateTime(today.year, today.month, 1);
        break;
      default:
        first = DateTime(today.year, today.month, today.day);
    }
    final from = _dayKey(first);
    final to = _dayKey(today);
    var result = 0;
    for (final row in logs) {
      final date = row['date']?.toString() ?? '';
      if (date.compareTo(from) < 0 || date.compareTo(to) > 0) continue;
      switch (metric) {
        case 'count':
          result += row['count_value'] as int? ?? 0;
          break;
        case 'duration':
          result += row['duration_min'] as int? ?? 0;
          break;
        default:
          result++;
      }
    }
    return result;
  }

  static bool met(Map<String, dynamic> habit, int progress) {
    final value = habit['goal_value'] as int? ?? 0;
    return value > 0 && progress >= value;
  }
}
