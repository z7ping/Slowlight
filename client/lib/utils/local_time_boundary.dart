/// Local Data 的时间语义：
///
/// - instant（created_at/completed_at/occurred_at/ended_at）统一以 UTC ISO8601 存储；
/// - due_date / HabitLog.date 是纯日历日期，不做 UTC 转换；
/// - “今天/本周”先按设备本地时区确定日历边界，再转成 UTC 查询 instant。
class LocalTimeBoundary {
  const LocalTimeBoundary._();

  static DateTime nowUtc() => DateTime.now().toUtc();

  static String instant(DateTime value) => value.toUtc().toIso8601String();

  static DateTime dayStart(DateTime local) =>
      DateTime(local.year, local.month, local.day);

  /// Advance a *calendar* date rather than an elapsed 24-hour duration.
  /// Local days can have 23 or 25 hours across UTC offset transitions.
  static DateTime addCalendarDays(DateTime local, int days) =>
      DateTime(local.year, local.month, local.day + days);

  static DateTime dayEnd(DateTime local) => addCalendarDays(local, 1);

  static DateTime weekStart(DateTime local) {
    final start = dayStart(local);
    return addCalendarDays(start, 1 - start.weekday);
  }

  static DateTime monthStart(DateTime local) =>
      DateTime(local.year, local.month, 1);

  static UtcRange dayRange(DateTime local) =>
      UtcRange.fromLocal(dayStart(local), dayEnd(local));

  static UtcRange range(DateTime localStart, DateTime localEnd) =>
      UtcRange.fromLocal(localStart, localEnd);

  static String dateKey(DateTime local) =>
      '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';

  static DateTime? parseInstant(Object? raw) {
    if (raw == null) return null;
    final value = DateTime.tryParse(raw.toString());
    return value?.toLocal();
  }
}

class UtcRange {
  final DateTime localStart;
  final DateTime localEnd;
  final String startUtc;
  final String endUtc;

  UtcRange.fromLocal(this.localStart, this.localEnd)
      : startUtc = localStart.toUtc().toIso8601String(),
        endUtc = localEnd.toUtc().toIso8601String();

  bool contains(DateTime instant) {
    final value = instant.toUtc();
    final start = localStart.toUtc();
    final end = localEnd.toUtc();
    return !value.isBefore(start) && value.isBefore(end);
  }
}
