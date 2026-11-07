/// HabitLog.date 是用户日历日期，不是时间点；createdAt 才是 UTC instant。
class HabitLog {
  final int id;
  final int habitId;
  final String date;
  final String? occurrenceKey;
  final String period;
  final int durationMin;
  final int? countValue;
  final DateTime? occurredAt;
  final String note;
  final DateTime createdAt;

  const HabitLog({
    required this.id,
    required this.habitId,
    required this.date,
    this.occurrenceKey,
    required this.period,
    required this.durationMin,
    this.countValue,
    this.occurredAt,
    required this.note,
    required this.createdAt,
  });

  /// An absent/malformed response cannot be interpreted as confirmed
  /// zero history. The screen keeps its last authoritative snapshot on error.
  static List<HabitLog> parseHistory(Object? raw) {
    if (raw is! List) {
      throw const FormatException('习惯记录响应缺少 logs 数组');
    }
    final result = <HabitLog>[];
    for (final value in raw) {
      if (value is! Map) {
        throw const FormatException('习惯记录包含无效条目');
      }
      final row = Map<String, dynamic>.from(value);
      final id = row['id'];
      final habitId = row['habit_id'];
      final date = row['date'];
      if (id is! int || id == 0 || habitId is! int || habitId == 0 ||
          date is! String || !_isValidDay(date)) {
        throw const FormatException('习惯记录缺少有效身份或日期');
      }
      result.add(HabitLog.fromJson(row));
    }
    return result;
  }

  static bool _isValidDay(String value) {
    if (!RegExp(r'^\\d{4}-\\d{2}-\\d{2}
    return HabitLog(
      id: json['id'] as int? ?? 0,
      habitId: json['habit_id'] as int? ?? 0,
      date: json['date'] as String? ?? '',
      occurrenceKey: json['occurrence_key'] as String?,
      period: json['period'] as String? ?? '',
      durationMin: json['duration_min'] as int? ?? 0,
      countValue: json['count_value'] as int?,
      occurredAt: json['occurred_at'] == null || json['occurred_at'] == ''
          ? null : DateTime.parse(json['occurred_at'].toString()).toLocal(),
      note: json['note'] as String? ?? '',
      createdAt: json['created_at'] == null
          ? DateTime.now()
          : DateTime.parse(json['created_at'].toString()).toLocal(),
    );
  }
}
).hasMatch(value)) return false;
    final parsed = DateTime.tryParse(value);
    return parsed != null &&
        '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}' == value;
  }

  /// All storage modes and the server use the same YYYY-MM filter contract.
  static void validateMonth(String? month) {
    if (month != null &&
        !RegExp(r'^\\d{4}-(0[1-9]|1[0-2])
    return HabitLog(
      id: json['id'] as int? ?? 0,
      habitId: json['habit_id'] as int? ?? 0,
      date: json['date'] as String? ?? '',
      occurrenceKey: json['occurrence_key'] as String?,
      period: json['period'] as String? ?? '',
      durationMin: json['duration_min'] as int? ?? 0,
      countValue: json['count_value'] as int?,
      occurredAt: json['occurred_at'] == null || json['occurred_at'] == ''
          ? null : DateTime.parse(json['occurred_at'].toString()).toLocal(),
      note: json['note'] as String? ?? '',
      createdAt: json['created_at'] == null
          ? DateTime.now()
          : DateTime.parse(json['created_at'].toString()).toLocal(),
    );
  }
}
).hasMatch(month)) {
      throw const FormatException('month 应为 YYYY-MM');
    }
  }

  factory HabitLog.fromJson(Map<String, dynamic> json) {
    return HabitLog(
      id: json['id'] as int? ?? 0,
      habitId: json['habit_id'] as int? ?? 0,
      date: json['date'] as String? ?? '',
      occurrenceKey: json['occurrence_key'] as String?,
      period: json['period'] as String? ?? '',
      durationMin: json['duration_min'] as int? ?? 0,
      countValue: json['count_value'] as int?,
      occurredAt: json['occurred_at'] == null || json['occurred_at'] == ''
          ? null : DateTime.parse(json['occurred_at'].toString()).toLocal(),
      note: json['note'] as String? ?? '',
      createdAt: json['created_at'] == null
          ? DateTime.now()
          : DateTime.parse(json['created_at'].toString()).toLocal(),
    );
  }
}
