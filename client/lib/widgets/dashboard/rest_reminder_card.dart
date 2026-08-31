import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../ui/fx.dart';

/// 休息提醒统计数据
class RestReminderStats {
  final int workMinutes;
  final int restMinutes;
  final int workCount;
  final int restCount;
  final int skippedCount;
  final bool isActive;

  RestReminderStats({
    required this.workMinutes,
    required this.restMinutes,
    required this.workCount,
    required this.restCount,
    required this.skippedCount,
    required this.isActive,
  });

  factory RestReminderStats.fromJson(Map<String, dynamic> json) {
    return RestReminderStats(
      workMinutes: json['total_work_seconds'] != null
          ? (json['total_work_seconds'] as int) ~/ 60
          : 0,
      restMinutes: json['total_break_seconds'] != null
          ? (json['total_break_seconds'] as int) ~/ 60
          : 0,
      workCount: json['work_count'] ?? 0,
      restCount: json['rest_count'] ?? 0,
      skippedCount: json['skipped_count'] ?? 0,
      isActive: json['is_active'] ?? false,
    );
  }

  /// 是否休息不足（工作时间超过 2 小时，休息时间不足 15 分钟）
  bool get isRestInsufficient => workMinutes > 120 && restMinutes < 15;

  /// 工作休息比例
  double get workRestRatio => restMinutes > 0 ? workMinutes / restMinutes : 0;
}

/// 休息提醒统计卡片组件
class RestReminderCard extends StatelessWidget {
  final RestReminderStats? stats;
  final VoidCallback? onStartRest;
  final VoidCallback? onViewDetails;

  const RestReminderCard({
    super.key,
    this.stats,
    this.onStartRest,
    this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    if (stats == null) {
      return const SizedBox.shrink();
    }

    final isWarning = stats!.isRestInsufficient;

    return FxCard(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Icon(
                isWarning ? Icons.warning_amber : Icons.self_improvement,
                color: isWarning ? AppTheme.warning : AppTheme.success,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '工作与休息',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (stats!.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '进行中',
                    style: TextStyle(
                      fontSize: SlowlightTypography.captionSize,
                      color: AppTheme.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 统计数据
          Row(
            children: [
              // 工作时间
              Expanded(
                child: _buildStatItem(
                  context,
                  icon: Icons.work_outline,
                  label: '工作',
                  value: _formatMinutes(stats!.workMinutes),
                  color: AppTheme.info,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              // 休息时间
              Expanded(
                child: _buildStatItem(
                  context,
                  icon: Icons.coffee_outlined,
                  label: '休息',
                  value: _formatMinutes(stats!.restMinutes),
                  color: AppTheme.success,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              // 轮次
              Expanded(
                child: _buildStatItem(
                  context,
                  icon: Icons.repeat,
                  label: '轮次',
                  value: '${stats!.workCount}',
                  color: AppTheme.warmGray500,
                ),
              ),
            ],
          ),

          // 警告提示
          if (isWarning) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber,
                    size: 16,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已经工作 ${_formatMinutes(stats!.workMinutes)}，休息不足！建议休息 15 分钟。',
                      style: TextStyle(
                        fontSize: SlowlightTypography.secondarySize,
                        color: AppTheme.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FxButton(
                label: '开始休息',
                icon: Icons.coffee,
                variant: FxButtonVariant.secondary,
                onPressed: onStartRest,
              ),
            ),
          ],

          // 跳过次数
          if (stats!.skippedCount > 0) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                '今日跳过 ${stats!.skippedCount} 次休息',
                style: TextStyle(
                  fontSize: SlowlightTypography.captionSize,
                  color: AppTheme.warmGray500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: SlowlightTypography.bodySize,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: SlowlightTypography.captionSize,
            color: AppTheme.warmGray500,
          ),
        ),
      ],
    );
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) {
      return '$minutes 分钟';
    }
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) {
      return '$hours 小时';
    }
    return '$hours 小时 $mins 分';
  }
}
