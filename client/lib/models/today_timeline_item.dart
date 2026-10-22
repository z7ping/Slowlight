/// 单条可追溯的今日事实。展示数据来自 BehaviorEvent 或 Reflection，
/// 不在客户端合成不存在的行动，也不缓存第二份事实。
class TodayTimelineItem {
  final String id;
  final String kind;
  final String title;
  final int durationMinutes;
  final DateTime occurredAt;

  const TodayTimelineItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.durationMinutes,
    required this.occurredAt,
  });

  static TodayTimelineItem? fromJson(Map<String, dynamic> json) {
    final instant = DateTime.tryParse(json['occurred_at']?.toString() ?? '');
    if (instant == null) return null;
    return TodayTimelineItem(
      id: json['id']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      durationMinutes: (json['duration_min'] as num?)?.toInt() ?? 0,
      occurredAt: instant.toLocal(),
    );
  }

  String get category => switch (kind) {
    'task_completed' => '任务',
    'habit_checked' => '习惯',
    'session_ended' => '专注',
    'observation' => '观察',
    'reflection' => '反思',
    _ => '记录',
  };

  String get description => switch (kind) {
    'task_completed' => title.isEmpty ? '完成了一项任务' : '完成了$title',
    'habit_checked' => title.isEmpty ? '记录了一次习惯' : '记录了$title',
    'session_ended' => durationMinutes > 0
        ? '专注 $durationMinutes 分钟'
        : '结束一次专注',
    _ => title,
  };

  String get timeLabel =>
      '${occurredAt.hour.toString().padLeft(2, '0')}:${occurredAt.minute.toString().padLeft(2, '0')}';

  static List<TodayTimelineItem> sorted(Iterable<TodayTimelineItem> items) {
    final result = items.toList(growable: false);
    return result..sort((a, b) {
      final byTime = b.occurredAt.compareTo(a.occurredAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  }
}
