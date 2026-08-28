import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 习惯打卡月度热力图组件
/// 类似 GitHub 贡献热力图，按月展示
class HabitHeatmap extends StatelessWidget {
  /// 打卡日期列表
  final List<DateTime> checkInDates;

  /// 习惯颜色（热力图主色）
  final Color color;

  /// 展示的月份（默认当前月）
  final DateTime? month;

  const HabitHeatmap({
    super.key,
    required this.checkInDates,
    required this.color,
    this.month,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final targetMonth = month ?? now;
    final year = targetMonth.year;
    final m = targetMonth.month;

    // 月份第一天和最后一天
    final firstDay = DateTime(year, m, 1);
    final lastDay = DateTime(year, m + 1, 0);

    // 将打卡日期标准化为只含年月日的集合，方便查找
    final checkInSet = checkInDates
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();

    // 统计每条打卡次数（用于强度计算）
    final checkInCount = <DateTime, int>{};
    for (final d in checkInDates) {
      final key = DateTime(d.year, d.month, d.day);
      checkInCount[key] = (checkInCount[key] ?? 0) + 1;
    }
    final maxCount = checkInCount.values.fold<int>(1, (a, b) => a > b ? a : b);

    // 计算日历网格：从该月第一周的周一开始
    // Dart weekday: 1=Monday ... 7=Sunday
    final gridStart = firstDay.subtract(Duration(days: firstDay.weekday - 1));
    // 计算需要多少周
    final totalDays = lastDay.difference(gridStart).inDays + 1;
    final weeks = (totalDays / 7).ceil();

    // 今天（仅年月日）
    final today = DateTime(now.year, now.month, now.day);

    // 月份标签
    final monthLabel = _monthLabel(m);

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 3.0;
        const maxCellSize = 28.0;
        // 7 列，6 个间距
        final desiredSize = (constraints.maxWidth - gap * 6) / 7;
        final cellSize = desiredSize > maxCellSize ? maxCellSize : desiredSize;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 月份标签
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                monthLabel,
                style: TextStyle(
                  fontSize: AppTheme.textMd, height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.warmDark,
                ),
              ),
            ),

            // 星期表头
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(7, (i) {
                return SizedBox(
                  width: i < 6 ? cellSize + gap : cellSize,
                  child: Center(
                    child: Text(
                      _weekdayLabel(i),
                      style: TextStyle(
                        fontSize: AppTheme.textXs, height: 1.4,
                        color: AppTheme.warmGray400,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 4),

            // 热力图网格
            ...List.generate(weeks, (weekIndex) {
              return Padding(
                padding: const EdgeInsets.only(bottom: gap),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(7, (dayIndex) {
                    final date = gridStart.add(Duration(days: weekIndex * 7 + dayIndex));
                    final isCurrentMonth = date.year == year && date.month == m;
                    final dateKey = DateTime(date.year, date.month, date.day);
                    final isToday = dateKey == today;
                    final isChecked = checkInSet.contains(dateKey);

                    // 计算强度（1~4级）
                    Color fillColor;
                    if (!isCurrentMonth) {
                      fillColor = Colors.transparent;
                    } else if (isChecked) {
                      final count = checkInCount[dateKey] ?? 1;
                      final ratio = count / maxCount;
                      fillColor = _intensityColor(ratio);
                    } else {
                      fillColor = AppTheme.warmWhite;
                    }

                    return Padding(
                      padding: EdgeInsets.only(right: dayIndex < 6 ? gap : 0),
                      child: Container(
                        width: cellSize,
                        height: cellSize,
                        decoration: BoxDecoration(
                          color: fillColor,
                          borderRadius: BorderRadius.circular(4),
                          border: isToday
                              ? Border.all(color: color, width: 1.5)
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  /// 根据强度比例返回不同深度的颜色
  Color _intensityColor(double ratio) {
    if (ratio <= 0.25) {
      return color.withValues(alpha: 0.2);
    } else if (ratio <= 0.5) {
      return color.withValues(alpha: 0.4);
    } else if (ratio <= 0.75) {
      return color.withValues(alpha: 0.7);
    } else {
      return color;
    }
  }

  /// 月份标签
  String _monthLabel(int month) {
    const labels = [
      '', '1月', '2月', '3月', '4月', '5月', '6月',
      '7月', '8月', '9月', '10月', '11月', '12月',
    ];
    return labels[month];
  }

  /// 星期标签（周一开始）
  String _weekdayLabel(int index) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return labels[index];
  }
}
