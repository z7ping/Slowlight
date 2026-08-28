/// HabitLog.date 是用户日历日期，不是时间点；createdAt 才是 UTC instant。
class HabitLog {
  final int id;
  final int habitId;
  final String date;
  final String period;
  final int durationMin;
  final String note;
  final DateTime createdAt;

  const HabitLog({
    required this.id,
    required this.habitId,
    required this.date,
    required this.period,
    required this.durationMin,
    required this.note,
    required this.createdAt,
  });

  factory HabitLog.fromJson(Map<String, dynamic> json) {
    return HabitLog(
      id: json['id'] as int? ?? 0,
      habitId: json['habit_id'] as int? ?? 0,
      date: json['date'] as String? ?? '',
      period: json['period'] as String? ?? '',
      durationMin: json['duration_min'] as int? ?? 0,
      note: json['note'] as String? ?? '',
      createdAt: json['created_at'] == null
          ? DateTime.now()
          : DateTime.parse(json['created_at'].toString()).toLocal(),
    );
  }
}
