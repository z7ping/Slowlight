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
