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
  /// Saved revisions only. Missing legacy versions never imply past targets.
  final List<Map<String, dynamic>> goalHistory;
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
  final String? offScheduleDate;
  final int periodCount;
  final int periodTarget;
  final List<String> checkedDays;
  final DateTime createdAt;
  /// Only populated in search results. Never persisted on the habit itself.
  final String searchNote;
  final DateTime? searchNoteAt;

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
    this.goalHistory = const [],
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
    this.offScheduleDate,
    this.periodCount = 0,
    this.periodTarget = 0,
    this.checkedDays = const [],
    required this.createdAt,
    this.searchNote = '',
    this.searchNoteAt,
  });

  bool get allowsMultipleRecordsToday {
    if (scheduleRule.isEmpty) return allowMultiplePerDay;
    final rule = HabitScheduleRule.fromJson(scheduleRule, legacyFrequency: frequency);
    return rule.kind == 'goal' && rule.sameDayMultiple;
  }

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
      goalHistory: _parseGoalHistory(json['goal_history']),
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
      offScheduleDate: json['off_schedule_date'] as String?,
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
      searchNote: json['search_note'] as String? ?? '',
      searchNoteAt: DateTime.tryParse(
        json['search_note_at']?.toString() ?? '',
      )?.toLocal(),
    );
  }

  static List<Map<String, dynamic>> _parseGoalHistory(dynamic raw) {
    if (raw == null) return const [];
    final value = raw is String ? jsonDecode(raw) : raw;
    if (value is! List) {
      throw const FormatException('历史目标版本格式不正确');
    }
    return value.map((item) {
      if (item is! Map) {
        throw const FormatException('历史目标版本包含无效记录');
      }
      return Map<String, dynamic>.from(item);
    }).toList(growable: false);
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
      // Old custom rows sometimes contain an incomplete rule object.
      // Do not turn parser defaults into an invented "每天" or time window.
      if (frequency == 'custom') {
        final kind = scheduleRule['kind'];
        final unit = scheduleRule['unit'];
        if (kind is! String || unit is! String ||
            scheduleRule['every'] is! int ||
            scheduleRule['anchor_date'] is! String ||
            (kind == 'goal' && scheduleRule['target_count'] is! int) ||
            (kind == 'interval' && unit == 'hour' &&
                scheduleRule['hour_mode'] is! String)) {
          return '';
        }
      }
      return HabitScheduleRule.fromJson(
        scheduleRule,
        legacyFrequency: frequency,
      ).summary;
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
        // Legacy custom / unknown frequencies without a saved V3 rule
        // cannot be explained truthfully: omit them rather than showing an enum.
        return '';
    }
  }

  /// 是否启用提醒。兼容旧 reminderAt 只保存 hour/minute 的数据。
  bool get reminderEnabled =>
      reminderAt['enabled'] == true || reminderAt.containsKey('hour');

  int get reminderAdvanceMinutes =>
      reminderAt['advance_minutes'] as int? ?? 0;
}
