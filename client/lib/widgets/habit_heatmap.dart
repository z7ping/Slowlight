import 'package:flutter/material.dart';

import '../ui/fx.dart';

/// Android month heatmap: a responsive seven-column matrix of read-only
/// squares. The viewport width, not a hardcoded cell size, owns geometry.
class HabitHeatmap extends StatelessWidget {
  const HabitHeatmap({
    super.key,
    required this.checkInDates,
    required this.color,
    this.month,
  });

  final List<DateTime> checkInDates;
  final Color color;
  final DateTime? month;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final target = month ?? now;
    final year = target.year;
    final m = target.month;
    final startOfMonth = DateTime(year, m, 1);
    final firstGridDay = startOfMonth.subtract(
      Duration(days: startOfMonth.weekday - 1),
    );
    final leading = startOfMonth.weekday - 1;
    final daysInMonth = DateTime(year, m + 1, 0).day;
    final numberOfCells = ((leading + daysInMonth + 6) ~/ 7) * 7;
    final counts = <DateTime, int>{};
    for (final day in checkInDates) {
      final key = DateTime(day.year, day.month, day.day);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final maxCount = counts.values.fold<int>(
      1, (maximum, count) => count > maximum ? count : maximum,
    );
    final theme = Theme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final today = DateTime(now.year, now.month, now.day);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$m 月 · $year',
            style: SlowlightTypography.caption(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: SlowlightSpacing.xs),
          if (!largeText) ...[
            Row(
              children: weekdays
                  .map((label) => Expanded(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: SlowlightTypography.caption(context).copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ))
                  .toList(growable: false),
            ),
            const SizedBox(height: SlowlightSpacing.xs),
          ],
          GridView.builder(
            key: const ValueKey('habit-month-heatmap-grid'),
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: numberOfCells,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              final date = firstGridDay.add(Duration(days: index));
              if (date.month != m || date.year != year) {
                return const SizedBox.shrink();
              }
              final key = DateTime(date.year, date.month, date.day);
              final count = counts[key] ?? 0;
              final isToday = key == today;
              final intensity = count == 0
                  ? theme.colorScheme.surfaceContainerLow
                  : color.withValues(
                      alpha: .25 + .7 * count / maxCount,
                    );
              return Semantics(
                key: ValueKey(
                  'habit-heatmap-day-$year-'
                  '${m.toString().padLeft(2, '0')}-'
                  '${date.day.toString().padLeft(2, '0')}',
                ),
                label: '${date.month}月${date.day}日'
                    '${count == 0 ? '无记录' : '$count 条记录'}',
                image: true,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: intensity,
                    borderRadius: BorderRadius.circular(SlowlightRadius.sm),
                    border: isToday
                        ? Border.all(
                            color: theme.colorScheme.onSurfaceVariant,
                            width: 1.5,
                          )
                        : null,
                  ),
                ),
              );
            },
          ),
        ],
    );
  }
}
