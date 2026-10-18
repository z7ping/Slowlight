import 'package:flutter/material.dart';

import '../../ui/typography_tokens.dart';

/// 回顾页专属时间线项。
///
/// 时间线表达“今天真实发生了什么”，属于 Review Feature Widget，
/// 不进入全局 Fx 基础组件层。
class ReviewTimelineItem extends StatelessWidget {
  final Color color;
  final String time;
  final String title;
  final String? note;
  final bool last;

  const ReviewTimelineItem({
    super.key,
    required this.color,
    required this.time,
    required this.title,
    this.note,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 14,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    time,
                    style: SlowlightTypography.caption(context).copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: SlowlightTypography.body(context).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (note != null && note!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      note!,
                      style: SlowlightTypography.caption(context).copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

 
/// 时间已知的事实按发生时刻排列；只有“今天”的汇总放在最后。
int compareReviewTimelineItems(ReviewTimelineItem a, ReviewTimelineItem b) {
  int? minutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null ||
        hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  final first = minutes(a.time);
  final second = minutes(b.time);
  if (first == null) return second == null ? 0 : 1;
  if (second == null) return -1;
  return first.compareTo(second);
}
