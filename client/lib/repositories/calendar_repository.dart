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
  final Future<List<Task>> Function(int year, int month)? _taskLoader;
  final Future<List<Task>> Function()? _completedTaskLoader;

  CalendarRepository({
    HabitRepository? habitRepository,
    ReflectionRepository? reflectionRepository,
    SessionRepository? sessionRepository,
    Future<List<Task>> Function(int year, int month)? taskLoader,
    Future<List<Task>> Function()? completedTaskLoader,
  })  : _habitRepository = habitRepository ?? HabitRepository(),
        _reflectionRepository = reflectionRepository ?? ReflectionRepository(),
        _sessionRepository = sessionRepository ?? SessionRepository(),
        _taskLoader = taskLoader,
        _completedTaskLoader = completedTaskLoader;

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
    // A due date is a civil *plan*, never the date a task was completed.
    // Actual task facts use completed_at and retain their own identity.
    void addTask(Task task) {
      final due = task.dueDate;
      final completedAt = task.isCompleted ? task.completedAt?.toLocal() : null;
      final completionInMonth =
          completedAt != null && _inMonth(completedAt, month);
      if (due != null && _inMonth(due, month) &&
          !(completionInMonth && _sameCivilDay(due, completedAt))) {
        final id = 'task-${task.id}-plan';
        if (!target.any((row) => row.id == id)) {
          target.add(_taskPlan(task, due));
        }
      }
      if (completionInMonth) {
        final id = 'task-${task.id}-actual';
        if (!target.any((row) => row.id == id)) {
          target.add(_taskActual(task, completedAt));
        }
        // The calendar shouldn't show two entries when a plan and its
        // actual completion belong to the same civil day.
        target.removeWhere((row) =>
            row.id == 'task-${task.id}-plan' &&
            _sameCivilDay(row.date, completedAt));
      }
    }

    try {
      final scheduled = await (_taskLoader?.call(month.year, month.month) ??
          ApiService.getTasksForMonth(month.year, month.month));
      for (final task in scheduled) {
        addTask(task);
      }
    } catch (_) {
      unavailable.add(CalendarRecordType.task);
    }
    // Use the existing completed-tasks endpoint rather than changing the
    // shared task-month API owned by the P06 workstream. Injected calendar
    // tests may supply an already complete task sample.
    if (_taskLoader != null && _completedTaskLoader == null) return;
    try {
      final completed = await (_completedTaskLoader?.call() ??
          ApiService.getCompletedTasks());
      for (final task in completed) {
        if (task.isCompleted) addTask(task);
      }
    } catch (_) {
      unavailable.add(CalendarRecordType.task);
    }
  }

  bool _sameCivilDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  CalendarRecord _taskPlan(Task task, DateTime due) => CalendarRecord(
        id: 'task-${task.id}-plan',
        type: CalendarRecordType.task,
        kind: CalendarRecordKind.plan,
        date: DateTime(due.year, due.month, due.day),
        title: task.title,
        timeLabel: task.dueTime ?? '',
        description: task.description ?? '',
        colorHex: task.list?.color ?? '',
        priority: task.priority,
        completed: false,
        task: task,
      );

  CalendarRecord _taskActual(Task task, DateTime completedAt) => CalendarRecord(
        id: 'task-${task.id}-actual',
        type: CalendarRecordType.task,
        kind: CalendarRecordKind.actual,
        date: DateTime(completedAt.year, completedAt.month, completedAt.day),
        title: task.title,
        timeLabel: '${DateFormat('HH:mm').format(completedAt)} 完成',
        description: task.description ?? '',
        colorHex: task.list?.color ?? '',
        priority: task.priority,
        completed: true,
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
      // One unavailable habit must not erase records from all the other
      // habits. Mark the category partial and keep every confirmed log.
      await Future.wait(habits.map((habit) async {
        try {
          final logs = await _habitRepository.logs(
            habit.id,
            month: monthKey,
          );
          for (final log in logs) {
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
        } catch (_) {
          unavailable.add(CalendarRecordType.habit);
        }
      }));
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
      if (daily == null &&
          stats['total_work_seconds'] == 0 &&
          stats['work_count'] == 0) {
        return; // Confirmed no work sessions; Go omits empty daily.
      }
      if (daily is! List) {
        unavailable.add(CalendarRecordType.focus);
        return;
      }
      for (final raw in daily) {
        if (raw is! Map) {
          unavailable.add(CalendarRecordType.focus);
          continue;
        }
        final row = Map<String, dynamic>.from(raw);
        final date = DateTime.tryParse(row['date']?.toString() ?? '');
        final rawSeconds = row['work_seconds'];
        final rawCount = row['work_count'];
        if (date == null || rawSeconds is! num || rawCount is! num ||
            rawSeconds < 0 || rawCount < 0) {
          unavailable.add(CalendarRecordType.focus);
          continue;
        }
        final seconds = rawSeconds.toInt();
        final count = rawCount.toInt();
        if (seconds <= 0 || !_inMonth(date, month)) continue;
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
      final result = await _reflectionRepository.month(month);
      if (!result.complete) {
        unavailable.add(CalendarRecordType.reflection);
      }
      for (final entry in result.entries) {
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
