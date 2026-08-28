import 'dart:convert';

class Habit {
  final int id;
  final int userId;
  final String name;
  final String icon;
  final String color;
  final String frequency;
  final int targetDays;
  final int streakCount;
  final String preferredPeriod;
  final int? systemTagId;
  final bool generateTask;
  final bool showCheckinDialog;
  final int durationMin;
  final String specificTime;
  final Map<String, dynamic> reminderAt;
  final bool checkedToday;
  final List<String> checkedDays;
  final DateTime createdAt;

  Habit({
    required this.id,
    required this.userId,
    required this.name,
    this.icon = '✅',
    this.color = '#52c41a',
    this.frequency = 'daily',
    this.targetDays = 0,
    this.streakCount = 0,
    this.preferredPeriod = '',
    this.systemTagId,
    this.generateTask = false,
    this.showCheckinDialog = false,
    this.durationMin = 0,
    this.specificTime = '',
    this.reminderAt = const {},
    this.checkedToday = false,
    this.checkedDays = const [],
    required this.createdAt,
  });

  factory Habit.fromJson(Map<String, dynamic> json) {
    return Habit(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? 0,
      name: json['name'] ?? '',
      icon: json['icon'] ?? '✅',
      color: json['color'] ?? '#52c41a',
      frequency: json['frequency'] ?? 'daily',
      targetDays: json['target_days'] ?? 0,
      streakCount: json['streak_count'] ?? 0,
      preferredPeriod: json['preferred_period'] ?? '',
      systemTagId: json['system_tag_id'],
      generateTask: json['generate_task'] == true || json['generate_task'] == 1,
      showCheckinDialog:
          json['show_checkin_dialog'] == true || json['show_checkin_dialog'] == 1,
      durationMin: json['duration_min'] ?? 0,
      specificTime: json['specific_time'] ?? '',
      reminderAt: _parseReminderAt(json['reminder_at']),
      checkedToday:
          json['checked_today'] == true || json['checked_today'] == 1,
      checkedDays: (json['checked_days'] as List?)
              ?.map((value) => value.toString())
              .toList(growable: false) ??
          const [],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at']).toLocal()
          : DateTime.now(),
    );
  }

  static Map<String, dynamic> _parseReminderAt(dynamic value) {
    if (value == null) return {};
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(
          const JsonDecoder().convert(value) as Map,
        );
      } catch (_) {
        return {};
      }
    }
    return {};
  }

  String get frequencyText {
    switch (frequency) {
      case 'daily':
        return '每天';
      case 'weekly':
        return '每周';
      case 'monthly':
        return '每月';
      case 'yearly':
        return '每年';
      default:
        return frequency;
    }
  }

  /// 是否启用提醒。兼容旧 reminderAt 只保存 hour/minute 的数据。
  bool get reminderEnabled =>
      reminderAt['enabled'] == true || reminderAt.containsKey('hour');

  int get reminderAdvanceMinutes =>
      reminderAt['advance_minutes'] as int? ?? 0;
}
