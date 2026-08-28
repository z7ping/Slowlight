import 'task.dart';

enum CalendarRecordType { task, habit, focus, reflection }

enum CalendarRecordKind { plan, actual }

enum CalendarDisplayMode { all, plan, actual }

/// 日历月视图统一展示记录。
///
/// Task 表示计划或完成事实，HabitLog / WorkSession / Reflection 均表示实际记录。
class CalendarRecord {
  final String id;
  final CalendarRecordType type;
  final CalendarRecordKind kind;
  final DateTime date;
  final String title;
  final String timeLabel;
  final String description;
  final String colorHex;
  final String dimensionLabel;
  final int durationMin;
  final bool completed;
  final String priority;
  final Task? task;

  const CalendarRecord({
    required this.id,
    required this.type,
    required this.kind,
    required this.date,
    required this.title,
    this.timeLabel = '',
    this.description = '',
    this.colorHex = '',
    this.dimensionLabel = '',
    this.durationMin = 0,
    this.completed = false,
    this.priority = 'none',
    this.task,
  });

  String get typeLabel => switch (type) {
        CalendarRecordType.task => '任务',
        CalendarRecordType.habit => '习惯',
        CalendarRecordType.focus => '专注',
        CalendarRecordType.reflection => '观察',
      };

  String get kindLabel => kind == CalendarRecordKind.plan ? '计划' : '实际';
}

class CalendarMonthData {
  final DateTime month;
  final List<CalendarRecord> records;
  final Set<CalendarRecordType> unavailableTypes;

  const CalendarMonthData({
    required this.month,
    required this.records,
    this.unavailableTypes = const {},
  });
}

typedef CalendarMonthLoader = Future<CalendarMonthData> Function(
    DateTime month);
