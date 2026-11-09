import 'package:flutter/material.dart';

import '../ui/app_theme.dart';
import '../ui/typography_tokens.dart';

/// 今天与回顾共用的轻量事件类别标识。
///
/// 从回顾时间线原有的「彩色圆点 + 类别文字」提取，避免维护两套样式。
class TimelineTypeLabel extends StatelessWidget {
  final String kind;
  final Color? baseColor;

  const TimelineTypeLabel({
    super.key,
    required this.kind,
    this.baseColor,
  });

  static String labelFor(String kind) => switch (kind) {
    'task_completed' => '任务',
    'habit_checked' => '习惯',
    'observation' => '观察',
    'session_ended' => '专注',
    'reflection' => '反思',
    _ => '记录',
  };

  static Color baseColorFor(String kind) => switch (kind) {
    'task_completed' => AppTheme.chartGreen,
    'habit_checked' => AppTheme.chartYellow,
    'observation' => AppTheme.chartPurple,
    'session_ended' => AppTheme.info,
    _ => AppTheme.info,
  };

  /// 沿用回顾页已有的混色策略，兼顾亮色与暗色背景下的可读性。
  static Color resolvedColor(
    BuildContext context,
    String kind, {
    Color? baseColor,
  }) =>
      Color.lerp(
        baseColor ?? baseColorFor(kind),
        Theme.of(context).colorScheme.onSurface,
        .35,
      )!;

  @override
  Widget build(BuildContext context) {
    final color = resolvedColor(context, kind, baseColor: baseColor);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          labelFor(kind),
          style: SlowlightTypography.caption(context).copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
