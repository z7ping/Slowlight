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

  // Match the database's numeric-ID DESC tie break for stable pagination.
  static int _compareStableIds(String a, String b) {
    final aColon = a.indexOf(':');
    final bColon = b.indexOf(':');
    final aSource = aColon < 0 ? a : a.substring(0, aColon);
    final bSource = bColon < 0 ? b : b.substring(0, bColon);
    final source = aSource.compareTo(bSource);
    if (source != 0) return source;
    final aNumber = aColon < 0 ? null : int.tryParse(a.substring(aColon + 1));
    final bNumber = bColon < 0 ? null : int.tryParse(b.substring(bColon + 1));
    if (aNumber != null && bNumber != null) {
      return bNumber.compareTo(aNumber);
    }
    return b.compareTo(a);
  }

  static List<TodayTimelineItem> sorted(Iterable<TodayTimelineItem> items) {
    final result = items.toList(growable: false);
    return result..sort((a, b) {
      final byTime = b.occurredAt.compareTo(a.occurredAt);
      return byTime != 0 ? byTime : _compareStableIds(a.id, b.id);
    });
  }
}

/// A bounded set of actual period events plus an independent, untruncated
/// count of observations. Displayed events must never be counted as totals.
class ReviewPeriodTimeline {
  final List<TodayTimelineItem> items;
  final int observationCount;
  final bool hasMore;

  const ReviewPeriodTimeline({
    required this.items,
    required this.observationCount,
    this.hasMore = false,
  });

  factory ReviewPeriodTimeline.fromJson(Map<String, dynamic> json) {
    final entries = json['items'];
    final count = json['observation_count'];
    final hasMore = json['has_more'];
    if (entries is! List || count is! num || count < 0 ||
        (hasMore != null && hasMore is! bool)) {
      throw const FormatException('Invalid period timeline payload');
    }
    return ReviewPeriodTimeline(
      items: TodayTimelineItem.sorted(entries
          .whereType<Map>()
          .map((value) => TodayTimelineItem.fromJson(
                Map<String, dynamic>.from(value),
              ))
          .whereType<TodayTimelineItem>()),
      observationCount: count.toInt(),
      hasMore: hasMore == true,
    );
  }
}
