import '../../repositories/session_repository.dart';
import '../../services/api/analytics_api.dart';
import '../../services/api_service.dart';

/// StatsScreen 的只读数据快照。
///
/// Analytics 统一走 [AnalyticsApi]，WorkSession 统一走 [SessionRepository]；
/// 页面只负责展示，不再自己判断 Data Mode，也不再逐清单拉取全部 Task 重算统计。
class StatsSnapshot {
  final Map<String, dynamic> taskStats;
  final List<Map<String, dynamic>> dailyTrend;
  final List<dynamic> listStats;
  final List<dynamic> tagStats;
  final List<Map<String, dynamic>> habits;
  final Map<String, dynamic> sessionStats;
  final Map<String, dynamic> todaySessionStats;
  final Map<String, dynamic> reminderStats;
  final Map<String, dynamic> timeDistribution;
  final Map<String, dynamic> outputStats;

  const StatsSnapshot({
    required this.taskStats,
    required this.dailyTrend,
    required this.listStats,
    required this.tagStats,
    required this.habits,
    required this.sessionStats,
    required this.todaySessionStats,
    required this.reminderStats,
    required this.timeDistribution,
    required this.outputStats,
  });

  static Future<StatsSnapshot> load() async {
    final sessions = SessionRepository();
    final results = await Future.wait<dynamic>([
      _map(() => AnalyticsApi.getTaskStats()),
      _trend(() => AnalyticsApi.getDailyTrend(days: 30)),
      _list(() => AnalyticsApi.getListStats()),
      _list(() => AnalyticsApi.getTagStats()),
      _habits(() => ApiService.getHabits()),
      _map(() => sessions.getSessionStats(period: 'week')),
      _map(() => sessions.getTodaySessionStats()),
      _map(() => AnalyticsApi.getReminderStats(period: 'week')),
      _map(() => AnalyticsApi.getTimeDistribution()),
      _map(() => AnalyticsApi.getOutputStats(period: 'all')),
    ]);

    return StatsSnapshot(
      taskStats: results[0] as Map<String, dynamic>,
      dailyTrend: results[1] as List<Map<String, dynamic>>,
      listStats: results[2] as List<dynamic>,
      tagStats: results[3] as List<dynamic>,
      habits: results[4] as List<Map<String, dynamic>>,
      sessionStats: results[5] as Map<String, dynamic>,
      todaySessionStats: results[6] as Map<String, dynamic>,
      reminderStats: results[7] as Map<String, dynamic>,
      timeDistribution: results[8] as Map<String, dynamic>,
      outputStats: results[9] as Map<String, dynamic>,
    );
  }

  static Future<Map<String, dynamic>> _map(
    Future<Map<String, dynamic>> Function() load,
  ) async {
    try {
      return await load();
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<List<dynamic>> _list(
    Future<List<dynamic>> Function() load,
  ) async {
    try {
      return await load();
    } catch (_) {
      return <dynamic>[];
    }
  }

  static Future<List<Map<String, dynamic>>> _trend(
    Future<List<Map<String, dynamic>>> Function() load,
  ) async {
    try {
      return await load();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<List<Map<String, dynamic>>> _habits(
    Future<List<Map<String, dynamic>>> Function() load,
  ) async {
    try {
      return await load();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  int get totalTasks => (taskStats['total'] as num?)?.toInt() ?? 0;
  int get completedTasks => (taskStats['completed'] as num?)?.toInt() ?? 0;

  int completedOn(DateTime day) {
    final key = _date(day);
    for (final point in dailyTrend) {
      if (point['date'] == key) {
        return (point['task_completed'] as num?)?.toInt() ?? 0;
      }
    }
    return 0;
  }

  int get completedToday => completedOn(DateTime.now());

  int get completedThisWeek {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return dailyTrend.where((p) {
      final date = DateTime.tryParse(p['date'] as String? ?? '');
      return date != null && !date.isBefore(start);
    }).fold<int>(0, (sum, p) => sum + ((p['task_completed'] as num?)?.toInt() ?? 0));
  }

  int get completedThisMonth {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    return dailyTrend.where((p) {
      final date = DateTime.tryParse(p['date'] as String? ?? '');
      return date != null && !date.isBefore(start);
    }).fold<int>(0, (sum, p) => sum + ((p['task_completed'] as num?)?.toInt() ?? 0));
  }

  List<Map<String, dynamic>> get last7Trend {
    if (dailyTrend.length <= 7) return dailyTrend;
    return dailyTrend.sublist(dailyTrend.length - 7);
  }

  int get todayFocusMinutes {
    final seconds = (todaySessionStats['total_work_seconds'] as num?)?.toInt();
    if (seconds != null) return seconds ~/ 60;
    return (todaySessionStats['total_minutes'] as num?)?.toInt() ?? 0;
  }

  int get todayFocusCount =>
      (todaySessionStats['work_count'] as num?)?.toInt() ??
      (todaySessionStats['count'] as num?)?.toInt() ?? 0;

  int get habitCount => habits.length;

  int get checkedHabitsToday {
    final today = _date(DateTime.now());
    var count = 0;
    for (final habit in habits) {
      final checked = habit['checked_today'];
      if (checked == true || checked == 1 || habit['last_checkin'] == today) count++;
    }
    return count;
  }

  String get longestStreak {
    String name = '';
    var best = 0;
    for (final habit in habits) {
      final streak = (habit['streak_count'] as num?)?.toInt() ??
          (habit['streak'] as num?)?.toInt() ?? 0;
      if (streak > best) {
        best = streak;
        name = habit['name'] as String? ?? '';
      }
    }
    return best == 0 ? '暂无' : '$name · $best 天';
  }

  static String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
