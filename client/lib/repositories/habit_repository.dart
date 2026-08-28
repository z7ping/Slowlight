import '../models/habit.dart';
import '../models/habit_log.dart';
import '../services/cloud_api_service.dart';
import '../services/data_mode_manager.dart';
import '../services/data_source.dart';
import '../services/local_api_service.dart';

/// Habit 的统一数据边界。
///
/// 数据源内部仍可使用 JSON/SQLite row，但 UI 与领域层从这里开始使用强类型
/// Habit / HabitLog。
class HabitRepository {
  final ApiDataSource? _fixedDataSource;

  HabitRepository({ApiDataSource? dataSource}) : _fixedDataSource = dataSource;

  ApiDataSource get _dataSource => _fixedDataSource ??
      (DataModeManager().isLocal ? LocalApiService() : CloudApiService());

  Future<List<Habit>> getAll() async {
    final values = await _dataSource.getHabits();
    return values.map(Habit.fromJson).toList();
  }

  Future<Habit> create({
    required String name,
    String icon = '✅',
    String color = '#52c41a',
    String frequency = 'daily',
    int targetDays = 0,
    int? systemTagId,
    String preferredPeriod = '',
    int durationMin = 0,
    bool generateTask = false,
    bool showCheckinDialog = false,
    String specificTime = '',
    Map<String, dynamic>? reminderAt,
  }) async {
    final value = await _dataSource.createHabit(
      name: name,
      icon: icon,
      color: color,
      frequency: frequency,
      targetDays: targetDays,
      systemTagId: systemTagId,
      preferredPeriod: preferredPeriod,
      durationMin: durationMin,
      generateTask: generateTask,
      showCheckinDialog: showCheckinDialog,
      specificTime: specificTime,
      reminderAt: reminderAt,
    );
    return Habit.fromJson(value);
  }

  Future<Habit> update(
    Habit habit, {
    String? name,
    String? icon,
    String? color,
    String? frequency,
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
    await _dataSource.updateHabit(habit.id, {
      'name': name ?? habit.name,
      'icon': icon ?? habit.icon,
      'color': color ?? habit.color,
      'frequency': frequency ?? habit.frequency,
      'target_days': targetDays ?? habit.targetDays,
      'system_tag_id': updateSystemTag ? systemTagId : habit.systemTagId,
      'preferred_period': preferredPeriod ?? habit.preferredPeriod,
      'duration_min': durationMin ?? habit.durationMin,
      'generate_task': generateTask ?? habit.generateTask,
      'show_checkin_dialog': showCheckinDialog ?? habit.showCheckinDialog,
      'specific_time': specificTime ?? habit.specificTime,
      'reminder_at': reminderAt ?? habit.reminderAt,
    });

    final values = await getAll();
    for (final value in values) {
      if (value.id == habit.id) return value;
    }
    throw StateError('更新后未找到习惯: ${habit.id}');
  }

  Future<Map<String, dynamic>> checkIn(
    int habitId, {
    String note = '',
    String? date,
    int? durationMin,
    String? period,
  }) =>
      _dataSource.checkInHabit(
        habitId,
        note: note,
        date: date,
        durationMin: durationMin,
        period: period,
      );

  Future<Map<String, dynamic>> uncheckIn(int habitId) =>
      _dataSource.uncheckInHabit(habitId);

  Future<List<HabitLog>> logs(int habitId, {String? month}) async {
    final value = await _dataSource.getHabitLogs(habitId, month: month);
    final raw = value['logs'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => HabitLog.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<void> delete(int habitId) => _dataSource.deleteHabit(habitId);

  /// 旧调用方兼容；新 UI 禁止继续使用动态 Map。
  @Deprecated('Use getAll() which returns List<Habit>.')
  Future<List<Map<String, dynamic>>> getHabits() => _dataSource.getHabits();

  @Deprecated('Use create() which returns Habit.')
  Future<Map<String, dynamic>> createHabit({
    required String name,
    String icon = '✅',
    String color = '#52c41a',
    String frequency = 'daily',
    int targetDays = 0,
    int? systemTagId,
    String preferredPeriod = '',
    int durationMin = 0,
    bool generateTask = false,
    bool showCheckinDialog = false,
  }) =>
      _dataSource.createHabit(
        name: name,
        icon: icon,
        color: color,
        frequency: frequency,
        targetDays: targetDays,
        systemTagId: systemTagId,
        preferredPeriod: preferredPeriod,
        durationMin: durationMin,
        generateTask: generateTask,
        showCheckinDialog: showCheckinDialog,
        specificTime: '',
        reminderAt: null,
      );

  @Deprecated('Use checkIn().')
  Future<Map<String, dynamic>> checkInHabit(
    int habitId, {
    String note = '',
    String? date,
    int? durationMin,
    String? period,
  }) =>
      checkIn(
        habitId,
        note: note,
        date: date,
        durationMin: durationMin,
        period: period,
      );

  @Deprecated('Use uncheckIn().')
  Future<Map<String, dynamic>> uncheckInHabit(int habitId) => uncheckIn(habitId);

  @Deprecated('Use logs() which returns List<HabitLog>.')
  Future<Map<String, dynamic>> getHabitLogs(int habitId, {String? month}) =>
      _dataSource.getHabitLogs(habitId, month: month);

  @Deprecated('Use delete().')
  Future<void> deleteHabit(int habitId) => delete(habitId);
}
