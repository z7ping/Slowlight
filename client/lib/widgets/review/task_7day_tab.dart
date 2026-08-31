import 'package:flutter/material.dart';

import '../../services/api/analytics_api.dart';
import '../../services/api/review_api.dart';
import '../../theme/app_theme.dart';
import '../../ui/fx.dart';
import 'completed_task_item.dart';

class TaskWeekTab extends StatefulWidget {
  const TaskWeekTab({super.key});

  @override
  State<TaskWeekTab> createState() => _TaskWeekTabState();
}

class _TaskWeekTabState extends State<TaskWeekTab> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _trendDays = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        ReviewApi.getTasksReview(days: 7),
        AnalyticsApi.getDailyTrend(days: 7),
      ]);
      if (!mounted) return;
      setState(() {
        _data = results[0] as Map<String, dynamic>;
        _trendDays = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: FxCircularProgress());
    if (_error != null) return _buildError();

    final summary = Map<String, dynamic>.from(
      _data['summary'] as Map? ?? const {},
    );
    final dist = Map<String, dynamic>.from(
      _data['distribution'] as Map? ?? const {},
    );
    final tasks = (_data['completed_tasks'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

    return FxRefresh(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                children: [
                  _summaryCard(summary),
                  const SizedBox(height: 14),
                  _trendCard(),
                  if (dist.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _distributionCard(dist),
                  ],
                  if (tasks.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _taskList(tasks),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(Map<String, dynamic> summary) {
    final theme = Theme.of(context);
    final completed = (summary['completed_count'] as num?)?.toInt() ?? 0;
    final created = (summary['created_count'] as num?)?.toInt() ?? 0;
    final days = (summary['total_days'] as num?)?.toInt() ?? 7;
    final bestDay =
        summary['best_day'] is Map
            ? Map<String, dynamic>.from(summary['best_day'] as Map)
            : null;
    final bestCount = (bestDay?['completed'] as num?)?.toInt() ?? 0;

    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '近 7 天任务'),
          const SizedBox(height: 12),
          _stats([
            FxStatCell(value: '$completed', label: '完成'),
            FxStatCell(value: '$created', label: '新建'),
            FxStatCell(value: '$days', label: '统计天数'),
          ]),
          if (bestDay != null && bestCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              '↳ ${bestDay['date'] ?? ''}记录到 $bestCount 个完成任务',
              style: SlowlightTypography.caption(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stats(List<Widget> cells) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaled = MediaQuery.textScalerOf(
          context,
        ).scale(SlowlightTypography.secondarySize);
        final stacked =
            constraints.maxWidth < 560 ||
            scaled >= SlowlightTypography.secondarySize * 1.3;
        if (stacked) {
          return Column(
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                SizedBox(width: double.infinity, child: cells[i]),
                if (i != cells.length - 1) const SizedBox(height: 8),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              Expanded(child: cells[i]),
              if (i != cells.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _trendCard() {
    final theme = Theme.of(context);
    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '每日完成趋势', trailing: '近 7 天'),
          const SizedBox(height: 14),
          if (_trendDays.isEmpty)
            Text(
              '暂无趋势数据',
              style: SlowlightTypography.secondary(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            _bars(),
        ],
      ),
    );
  }

  Widget _bars() {
    final theme = Theme.of(context);
    final values = _trendDays
        .map((day) => (day['task_completed'] as num?)?.toInt() ?? 0)
        .toList(growable: false);
    final max = values.fold<int>(1, (a, b) => b > a ? b : a);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return SizedBox(
      height: 142,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (index) {
          final date = DateTime.tryParse(
            _trendDays[index]['date']?.toString() ?? '',
          );
          final label = date == null ? '' : weekdays[date.weekday - 1];
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${values[index]}',
                    style: SlowlightTypography.caption(
                      context,
                    ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    width: 20,
                    height: values[index] == 0 ? 3 : 76 * values[index] / max,
                    decoration: BoxDecoration(
                      color: activePalette.accent.withValues(alpha: .84),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(SlowlightRadius.sm),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    style: SlowlightTypography.caption(
                      context,
                    ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _distributionCard(Map<String, dynamic> dist) {
    final byType = Map<String, dynamic>.from(
      dist['by_task_type'] as Map? ?? const {},
    );
    final byQuality = Map<String, dynamic>.from(
      dist['by_quality'] as Map? ?? const {},
    );
    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '任务分布'),
          const SizedBox(height: 10),
          _chipGroup('类型', byType),
          if (byType.isNotEmpty && byQuality.isNotEmpty)
            const SizedBox(height: 10),
          _chipGroup('输出等级', byQuality),
        ],
      ),
    );
  }

  Widget _chipGroup(String label, Map<String, dynamic> data) {
    if (data.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: SlowlightTypography.caption(context).copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: data.entries
              .map(
                (entry) => FxChip(
                  label: '${entry.key} · ${entry.value}',
                  variant: FxChipVariant.secondary,
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _taskList(List<Map<String, dynamic>> tasks) {
    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FxSectionHeader(title: '完成任务', trailing: '${tasks.length} 条'),
          const SizedBox(height: 8),
          ...tasks.map((task) => CompletedTaskItemWidget(task: task)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('近 7 天回顾加载失败', style: SlowlightTypography.cardTitle(context)),
          const SizedBox(height: 12),
          FxButton(
            label: '重试',
            variant: FxButtonVariant.secondary,
            onPressed: _load,
          ),
        ],
      ),
    );
  }
}
