import 'package:flutter/foundation.dart';

import '../models/habit.dart';
import 'dart:math';
import '../models/habit_occurrence.dart';
import '../models/habit_log.dart';
import '../repositories/habit_repository.dart';

/// Habit 工具页的状态与用例编排。
///
/// Widget 只负责交互；数据模式切换、CRUD 与日志读取都停在 Repository 边界。
class HabitController extends ChangeNotifier {
  final HabitRepository _repository;

  HabitController({HabitRepository? repository})
      : _repository = repository ?? HabitRepository();

  List<Habit> _habits = const [];
  final Map<int, List<HabitLog>> _logs = {};
  final Set<int> _loadingLogIds = {};
  bool _loading = false;
  String? _error;

  List<Habit> get habits => _habits;
  bool get loading => _loading;
  String? get error => _error;
  bool isLoadingLogs(int habitId) => _loadingLogIds.contains(habitId);
  List<HabitLog> logsFor(int habitId) => _logs[habitId] ?? const [];

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _habits = await _repository.getAll();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> checkIn(
    Habit habit, {
    String note = '',
    String? date,
    int? durationMin,
    String? period,
    String? occurrenceKey,
  }) async {
    final eventKey = habit.scheduleRule.isNotEmpty &&
        HabitOccurrence.rule(habit.scheduleRule)?.sameDayMultiple == true
        ? 'event:' + DateTime.now().toUtc().microsecondsSinceEpoch.toString() +
            '-' + Random.secure().nextInt(0x7fffffff).toRadixString(16)
        : null;
    final result = await _repository.checkIn(
      habit.id,
      note: note,
      date: date,
      durationMin: durationMin,
      period: period,
      occurrenceKey: occurrenceKey ?? eventKey,
    );
    await load();
    if (_logs.containsKey(habit.id)) await loadLogs(habit.id);
    return result;
  }

  Future<Map<String, dynamic>> uncheckIn(Habit habit) async {
    final result = await _repository.uncheckIn(habit.id);
    await load();
    if (_logs.containsKey(habit.id)) await loadLogs(habit.id);
    return result;
  }

  Future<Habit> create({
    required String name,
    String icon = '✅',
    String color = '#52c41a',
    String frequency = 'daily',
    Map<String, dynamic>? scheduleRule,
    int targetDays = 0,
    int? systemTagId,
    String preferredPeriod = '',
    int durationMin = 0,
    bool generateTask = false,
    bool showCheckinDialog = false,
    String specificTime = '',
    Map<String, dynamic>? reminderAt,
  }) async {
    final created = await _repository.create(
      name: name,
      icon: icon,
      color: color,
      frequency: frequency,
      scheduleRule: scheduleRule,
      targetDays: targetDays,
      systemTagId: systemTagId,
      preferredPeriod: preferredPeriod,
      durationMin: durationMin,
      generateTask: generateTask,
      showCheckinDialog: showCheckinDialog,
      specificTime: specificTime,
      reminderAt: reminderAt,
    );
    await load();
    return created;
  }

  Future<void> update(
    Habit habit, {
    String? name,
    String? icon,
    String? color,
    String? frequency,
    Map<String, dynamic>? scheduleRule,
    int? targetDays,
    int? systemTagId,
    bool updateSystemTag = false,
    String? preferredPeriod,
    int? durationMin,
    bool? generateTask,
    bool? showCheckinDialog,
    String? specificTime,
    Map<String, dynamic>? reminderAt,
  }) async {
    await _repository.update(
      habit,
      name: name,
      icon: icon,
      color: color,
      frequency: frequency,
      targetDays: targetDays,
      systemTagId: systemTagId,
      updateSystemTag: updateSystemTag,
      preferredPeriod: preferredPeriod,
      durationMin: durationMin,
      generateTask: generateTask,
      showCheckinDialog: showCheckinDialog,
      specificTime: specificTime,
      reminderAt: reminderAt,
    );
    await load();
  }

  Future<void> delete(Habit habit) async {
    await _repository.delete(habit.id);
    _logs.remove(habit.id);
    await load();
  }

  Future<void> loadLogs(int habitId) async {
    if (_loadingLogIds.contains(habitId)) return;
    _loadingLogIds.add(habitId);
    notifyListeners();
    try {
      final now = DateTime.now();
      final month =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';
      _logs[habitId] = await _repository.logs(habitId, month: month);
    } finally {
      _loadingLogIds.remove(habitId);
      notifyListeners();
    }
  }
}
