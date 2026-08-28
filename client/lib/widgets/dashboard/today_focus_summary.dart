import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../ui/fx.dart';

/// 今日专注摘要组件
class TodayFocusSummary extends StatelessWidget {
  final int sessionCount;
  final int totalMinutes;
  final VoidCallback? onStartFocus;

  const TodayFocusSummary({
    super.key,
    required this.sessionCount,
    required this.totalMinutes,
    this.onStartFocus,
  });

  @override
  Widget build(BuildContext context) {
    return FxCard(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // 图标
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text('🍅', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          // 统计信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '今日专注',
                  style: TextStyle(
                    fontSize: AppTheme.textSm,
                    color: AppTheme.warmGray500,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '$sessionCount 个番茄',
                      style: TextStyle(
                        fontSize: AppTheme.textMd,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (totalMinutes > 0) ...[
                      Text(
                        ' · ',
                        style: TextStyle(
                          fontSize: AppTheme.textMd,
                          color: AppTheme.warmGray400,
                        ),
                      ),
                      Text(
                        '$totalMinutes 分钟',
                        style: TextStyle(
                          fontSize: AppTheme.textMd,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // 开始专注按钮
          if (onStartFocus != null)
            FxButton(
              label: '开始专注',
              variant: FxButtonVariant.secondary,
              size: FxButtonSize.sm,
              icon: Icons.play_arrow,
              onPressed: onStartFocus,
            ),
        ],
      ),
    );
  }
}
