import 'package:intl/intl.dart';

import '../models/calendar_record.dart';
import '../models/habit.dart';
import '../models/reflection_entry.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import 'habit_repository.dart';
import 'reflection_repository.dart';
import 'session_repository.dart';

/// 聚合日历需要的计划与行为事实；单一来源失败时保留其他来源。
class CalendarRepository {
  final HabitRepository _habitRepository;
  final ReflectionRepository _reflectionRepository;
  final SessionRepository _sessionRepository;

  CalendarRepository({
    HabitRepository? habitRepository,
    ReflectionRepository? reflectionRepository,
    SessionRepository? sessionRepository,
  })  : _habitRepository = habitRepository ?? HabitRepository(),
        _reflectionRepository = reflectionRepository ?? ReflectionRepository(),
        _sessionRepository = sessionRepository ?? SessionRepository();

  Future<CalendarMonthData> loadMonth(DateTime month) async {
    final normalized = DateTime(month.year, month.month, 1);
    final records = <CalendarRecord>[];
    final unavailable = <CalendarRecordType>{};

    await Future.wait([
      _appendTasks(normalized, records, unavailable),
      _appendHabits(normalized, records, unavailable),
      _appendFocus(normalized, records, unavailable),
      _appendReflections(normalized, records, unavailable),
    ]);
    records.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      if (a.kind != b.kind) return a.kind.index.compareTo(b.kind.index);
      return a.title.compareTo(b.title);
    });
    return CalendarMonthData(
      month: normalized,
      records: records,
      unavailableTypes: unavailable,
    );
  }

  Future<void> _appendTasks(
    DateTime month,
    List<CalendarRecord> target,
    Set<CalendarRecordType> unavailable,
  ) async {
    try {
      final tasks = await ApiService.getTasksForMonth(month.year, month.month);
      for (final task in tasks) {
        final due = task.dueDate?.toLocal();
        if (due == null) continue;
        target.add(_taskRecord(task, due));
      }
    } catch (_) {
      unavailable.add(CalendarRecordType.task);
    }
  }

  CalendarRecord _taskRecord(Task task, DateTime due) => CalendarRecord(
        id: 'task-${task.id}',
        type: CalendarRecordType.task,
        kind: task.isCompleted
            ? CalendarRecordKind.actual
            : CalendarRecordKind.plan,
        date: DateTime(due.year, due.month, due.day),
        title: task.title,
        timeLabel: task.dueTime ?? '',
        description: task.description ?? '',
        colorHex: task.list?.color ?? '',
        completed: task.isCompleted,
        priority: task.priority,
        task: task,
      );

  Future<void> _appendHabits(
    DateTime month,
    List<CalendarRecord> target,
    Set<CalendarRecordType> unavailable,
  ) async {
    try {
      final habits = await _habitRepository.getAll();
      final monthKey = DateFormat('yyyy-MM').format(month);
      final values = await Future.wait(
        habits.map((habit) async => (
              habit,
              await _habitRepository.logs(
                habit.id,
                month: monthKey,
              )
            )),
      );
      for (final value in values) {
        final habit = value.$1;
        for (final log in value.$2) {
          final date = DateTime.tryParse(log.date);
          if (date == null || !_inMonth(date, month)) continue;
          target.add(CalendarRecord(
            id: 'habit-${habit.id}-${log.id}-${log.date}',
            type: CalendarRecordType.habit,
            kind: CalendarRecordKind.actual,
            date: DateTime(date.year, date.month, date.day),
            title: '${habit.icon} ${habit.name}',
            timeLabel: habit.specificTime.isNotEmpty
                ? habit.specificTime
                : _periodLabel(log.period),
            description: log.note,
            colorHex: habit.color,
            durationMin:
                log.durationMin > 0 ? log.durationMin : habit.durationMin,
            completed: true,
          ));
        }
      }
    } catch (_) {
      unavailable.add(CalendarRecordType.habit);
    }
  }

  Future<void> _appendFocus(
    DateTime month,
    List<CalendarRecord> target,
    Set<CalendarRecordType> unavailable,
  ) async {
    try {
      final stats = await _sessionRepository.getSessionStats(period: 'all');
      final daily = stats['daily'];
      if (daily is! List) return;
      for (final raw in daily.whereType<Map>()) {
        final row = Map<String, dynamic>.from(raw);
        final date = DateTime.tryParse(row['date']?.toString() ?? '');
        final seconds = (row['work_seconds'] as num?)?.toInt() ?? 0;
        final count = (row['work_count'] as num?)?.toInt() ?? 0;
        if (date == null || seconds <= 0 || !_inMonth(date, month)) continue;
        target.add(CalendarRecord(
          id: 'focus-${DateFormat('yyyy-MM-dd').format(date)}',
          type: CalendarRecordType.focus,
          kind: CalendarRecordKind.actual,
          date: DateTime(date.year, date.month, date.day),
          title: count > 1 ? '深度专注 $count 次' : '深度专注',
          timeLabel: '实际记录',
          description: '来自专注计时的当日汇总。',
          colorHex: '#8B5CF6',
          durationMin: (seconds / 60).round(),
          completed: true,
        ));
      }
    } catch (_) {
      unavailable.add(CalendarRecordType.focus);
    }
  }

  Future<void> _appendReflections(
    DateTime month,
    List<CalendarRecord> target,
    Set<CalendarRecordType> unavailable,
  ) async {
    try {
      final entries = await _reflectionRepository.recent(limit: 100);
      for (final entry in entries) {
        final local = entry.createdAt.toLocal();
        if (!_inMonth(local, month)) continue;
        target.add(_reflectionRecord(entry, local));
      }
    } catch (_) {
      unavailable.add(CalendarRecordType.reflection);
    }
  }

  CalendarRecord _reflectionRecord(ReflectionEntry entry, DateTime local) {
    final firstLine = entry.content.split(RegExp(r'\r?\n')).first.trim();
    return CalendarRecord(
      id: 'reflection-${entry.id}',
      type: CalendarRecordType.reflection,
      kind: CalendarRecordKind.actual,
      date: DateTime(local.year, local.month, local.day),
      title: firstLine.isEmpty ? '一条回顾记录' : firstLine,
      timeLabel: DateFormat('HH:mm').format(local),
      description: entry.content,
      colorHex: '#F97316',
      dimensionLabel: entry.dimensionKey ?? '',
      completed: true,
    );
  }

  bool _inMonth(DateTime date, DateTime month) =>
      date.year == month.year && date.month == month.month;

  String _periodLabel(String period) => switch (period) {
        'morning' => '上午',
        'afternoon' => '下午',
        'evening' => '晚间',
        'night' => '夜间',
        _ => '',
      };
}
