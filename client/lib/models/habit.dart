import 'dart:convert';
import 'habit_schedule_rule.dart';

class Habit {
  final int id;
  final int userId;
  final String name;
  final String icon;
  final String color;
  final String frequency;
  final Map<String, dynamic> scheduleRule;
  /// 旧数据保持原有时长/时段语义；新习惯默认为 check。
  final String recordType;
  final String recordUnit;
  /// 非空时在打卡弹层采集真实发生时间，文案由用户配置。
  final String recordTimeLabel;
  final bool allowMultiplePerDay;
  final String goalPeriod;
  final String goalMetric;
  final int goalValue;
  final int goalProgress;
  final bool goalMet;
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
  final bool? canCheckIn;
  final int periodCount;
  final int periodTarget;
  final List<String> checkedDays;
  final DateTime createdAt;

  Habit({
    required this.id,
    required this.userId,
    required this.name,
    this.icon = '✅',
    this.color = '#52c41a',
    this.frequency = 'daily',
    this.scheduleRule = const {},
    this.recordType = 'legacy',
    this.recordUnit = '次',
    this.recordTimeLabel = '',
    this.allowMultiplePerDay = false,
    this.goalPeriod = 'none',
    this.goalMetric = 'events',
    this.goalValue = 0,
    this.goalProgress = 0,
    this.goalMet = false,
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
    this.canCheckIn,
    this.periodCount = 0,
    this.periodTarget = 0,
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
      scheduleRule: _parseReminderAt(json['schedule_rule']),
      recordType: json['record_type'] as String? ?? 'legacy',
      recordUnit: json['record_unit'] as String? ?? '次',
      recordTimeLabel: json['record_time_label'] as String? ?? '',
      allowMultiplePerDay: json['allow_multiple_per_day'] == true ||
          json['allow_multiple_per_day'] == 1,
      goalPeriod: json['goal_period'] as String? ?? 'none',
      goalMetric: json['goal_metric'] as String? ?? 'events',
      goalValue: json['goal_value'] as int? ?? 0,
      goalProgress: json['goal_progress'] as int? ?? 0,
      goalMet: json['goal_met'] == true || json['goal_met'] == 1,
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
      canCheckIn: json['can_check_in'] is bool ? json['can_check_in'] as bool : null,
      periodCount: json['period_count'] as int? ?? 0,
      periodTarget: json['period_target'] as int? ?? 0,
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
    if (scheduleRule.isNotEmpty) {
      return HabitScheduleRule.fromJson(scheduleRule, legacyFrequency: frequency).summary;
    }
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
