import 'package:flutter/material.dart';
import '../services/api/analytics_api.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';

/// 可嵌入的周回顾组件（无 Scaffold/AppBar）
class WeeklyReviewEmbed extends StatefulWidget {
  final bool dense;
  const WeeklyReviewEmbed({super.key, this.dense = false});

  @override
  State<WeeklyReviewEmbed> createState() => _WeeklyReviewEmbedState();
}

class _WeeklyReviewEmbedState extends State<WeeklyReviewEmbed> {
  bool _loading = true;
  Map<String, dynamic> _review = {};
  Map<String, dynamic> _outputStats = {};

  @override
  void initState() {
    super.initState();
    _loadReview();
  }

  Future<void> _loadReview() async {
    try {
      final results = await Future.wait([
        AnalyticsApi.getWeeklyReview(),
        AnalyticsApi.getOutputStats(
          period: 'week',
        ).catchError((_) => <String, dynamic>{}),
      ]);
      if (mounted) {
        setState(() {
          _review = results[0] as Map<String, dynamic>;
          _outputStats = results[1] as Map<String, dynamic>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: FxCircularProgress(strokeWidth: 2));
    }

    final weekStart = _review['week_start'] ?? '';
    final weekEnd = _review['week_end'] ?? '';

    return FxRefresh(
      onRefresh: _loadReview,
      color: AppTheme.primary,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          widget.dense ? 12 : 16,
          12,
          widget.dense ? 12 : 16,
          92,
        ),
        children: [
          if (weekStart.isNotEmpty && weekEnd.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '$weekStart ~ $weekEnd',
                style: SlowlightTypography.secondary(
                  context,
                ).copyWith(color: AppTheme.warmGray500),
              ),
            ),
          _buildWeekSummary(),
          const SizedBox(height: 12),
          _buildVsLastWeek(),
          const SizedBox(height: 12),
          _buildOutputStats(),
          const SizedBox(height: 12),
          _buildTimeDistribution(),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required String emoji,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Text(emoji, style: SlowlightTypography.pageTitle(context)),
        const SizedBox(height: 4),
        Text(
          value,
          style: SlowlightTypography.pageTitle(
            context,
          ).copyWith(fontWeight: FontWeight.bold, color: AppTheme.warmDark),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: SlowlightTypography.caption(
            context,
          ).copyWith(color: AppTheme.warmGray500),
        ),
      ],
    );
  }

  Widget _buildWeekSummary() {
    final habitChecked = (_review['habit_checked'] as num?)?.toInt() ?? 0;
    final taskCompleted = (_review['task_completed'] as num?)?.toInt() ?? 0;
    final focusMinutes = (_review['focus_minutes'] as num?)?.toInt() ?? 0;
    final h = focusMinutes ~/ 60;
    final m = focusMinutes % 60;

    return FxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本周记录',
            style: SlowlightTypography.secondary(
              context,
            ).copyWith(fontWeight: FontWeight.w600, color: AppTheme.warmDark),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                emoji: '🔥',
                value: '$habitChecked',
                label: '习惯打卡',
              ),
              _buildStatItem(
                emoji: '✅',
                value: '$taskCompleted',
                label: '完成任务',
              ),
              _buildStatItem(
                emoji: '⏱️',
                value: h > 0 ? '${h}h${m}m' : '${m}m',
                label: '专注时长',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeltaRow(String label, int current, int last) {
    final delta = current - last;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: SlowlightTypography.secondary(context)),
          const Spacer(),
          Text(
            '$current',
            style: SlowlightTypography.secondary(
              context,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          if (delta != 0)
            Text(
              delta > 0 ? '+$delta' : '$delta',
              style: SlowlightTypography.caption(
                context,
              ).copyWith(color: AppTheme.warmGray500),
            ),
        ],
      ),
    );
  }

  Widget _buildVsLastWeek() {
    final habitThis = (_review['habit_checked'] as num?)?.toInt() ?? 0;
    final habitLast = (_review['habit_last_week'] as num?)?.toInt() ?? 0;
    final taskThis = (_review['task_completed'] as num?)?.toInt() ?? 0;
    final taskLast = (_review['task_last_week'] as num?)?.toInt() ?? 0;
    final focusThis = (_review['focus_minutes'] as num?)?.toInt() ?? 0;
    final focusLast = (_review['focus_last_week'] as num?)?.toInt() ?? 0;

    return FxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '和上周比',
            style: SlowlightTypography.secondary(
              context,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _buildDeltaRow('习惯打卡', habitThis, habitLast),
          const SizedBox(height: 4),
          _buildDeltaRow('完成任务', taskThis, taskLast),
          const SizedBox(height: 4),
          _buildDeltaRow('专注时长(分钟)', focusThis, focusLast),
        ],
      ),
    );
  }

  Widget _buildOutputStats() {
    if (_outputStats.isEmpty) return const SizedBox.shrink();
    final totalCount = (_outputStats['total_count'] as num?)?.toInt() ?? 0;
    final byLevel = _outputStats['by_level'] as Map<String, dynamic>? ?? {};
    final byType = _outputStats['by_task_type'] as Map<String, dynamic>? ?? {};
    final milestones = (_outputStats['milestones'] as num?)?.toInt() ?? 0;
    final thisWeek = (_outputStats['this_week'] as num?)?.toInt() ?? 0;
    final thisMonth = (_outputStats['this_month'] as num?)?.toInt() ?? 0;

    if (totalCount == 0 && thisWeek == 0 && thisMonth == 0) {
      return const SizedBox.shrink();
    }

    return FxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '输出记录',
            style: SlowlightTypography.secondary(
              context,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(emoji: '📝', value: '$totalCount', label: '累计'),
              _buildStatItem(emoji: '📅', value: '$thisWeek', label: '本周'),
              _buildStatItem(emoji: '📆', value: '$thisMonth', label: '本月'),
            ],
          ),
          if (byLevel.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  byLevel.entries
                      .map(
                        (entry) => FxChip(
                          label: '${entry.key} 级 ${entry.value}',
                          variant: FxChipVariant.secondary,
                        ),
                      )
                      .toList(),
            ),
          ],
          if (byType.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  byType.entries
                      .map(
                        (entry) => FxChip(
                          label: '${_typeName(entry.key)} ${entry.value}',
                          variant: FxChipVariant.secondary,
                        ),
                      )
                      .toList(),
            ),
          ],
          if (milestones > 0) ...[
            const SizedBox(height: 12),
            Text(
              '里程碑 $milestones 个',
              style: SlowlightTypography.secondary(context),
            ),
          ],
        ],
      ),
    );
  }

  String _typeName(String type) {
    switch (type) {
      case 'main':
        return '主线';
      case 'branch':
        return '分支';
      case 'daily':
        return '日常';
      case 'explore':
        return '探索';
      default:
        return type;
    }
  }

  Widget _buildTimeDistribution() {
    final timeDistribution =
        (_review['time_distribution'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
    if (timeDistribution.isEmpty) return const SizedBox.shrink();

    return FxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '时间分布',
            style: SlowlightTypography.secondary(
              context,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ...timeDistribution.map((td) {
            final name = td['name'] ?? '';
            final icon = td['icon'] ?? '';
            final totalMin = (td['total_min'] as num?)?.toInt() ?? 0;
            final pct = (td['percent'] as num?)?.toDouble() ?? 0;
            final h = totalMin ~/ 60;
            final m = totalMin % 60;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      icon,
                      style: SlowlightTypography.secondary(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Text(
                      name,
                      style: SlowlightTypography.secondary(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: FxProgress(
                      value: (pct / 100).clamp(0.0, 1.0),
                      height: 6,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 60,
                    child: Text(
                      h > 0 ? '${h}h${m}m' : '${m}m',
                      style: SlowlightTypography.caption(
                        context,
                      ).copyWith(color: AppTheme.warmGray500),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
