import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/api/analytics_api.dart';
import '../../services/api/review_api.dart';
import '../../theme/app_theme.dart';
import '../../ui/fx.dart';
import 'completed_task_item.dart';

class TaskMonthTab extends StatefulWidget {
  /// Test seams only. Production reuses the existing Review/Analytics APIs.
  final Future<Map<String, dynamic>> Function()? tasksReviewLoader;
  final Future<List<Map<String, dynamic>>> Function()? dailyTrendLoader;

  const TaskMonthTab({
    super.key,
    this.tasksReviewLoader,
    this.dailyTrendLoader,
  });

  @override
  State<TaskMonthTab> createState() => _TaskMonthTabState();
}

class _TaskMonthTabState extends State<TaskMonthTab> {
  bool _loading = true;
  bool _hasConfirmedReview = false;
  String? _error;
  String? _refreshError;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _trendDays = const [];
  bool _trendLoadFailed = false;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() {
      _loading = !_hasConfirmedReview;
      _error = null;
      _refreshError = null;
    });

    // Primary 30-day task facts should not wait for an optional trend query.
    unawaited(_loadTrend(version));
    try {
      final result = await (widget.tasksReviewLoader ??
          () => ReviewApi.getTasksReview(days: 30))();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _data = result;
        _hasConfirmedReview = true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        if (_hasConfirmedReview) {
          _refreshError = error.toString();
        } else {
          _error = error.toString();
        }
        _loading = false;
      });
    }
  }

  Future<void> _loadTrend(int version) async {
    try {
      final trend = await (widget.dailyTrendLoader ??
          () => AnalyticsApi.getDailyTrend(days: 30))();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _trendDays = trend;
        _trendLoadFailed = false;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      // Do not erase a previously confirmed trend on a failed refresh.
      setState(() => _trendLoadFailed = true);
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
        .take(20)
        .toList(growable: false);

    final hasData =
        ((summary['completed_count'] as num?)?.toInt() ?? 0) > 0 ||
        ((summary['created_count'] as num?)?.toInt() ?? 0) > 0 ||
        tasks.isNotEmpty ||
        _trendDays.any(
          (day) =>
              ((day['task_completed'] as num?)?.toInt() ?? 0) > 0 ||
              ((day['habit_checked'] as num?)?.toInt() ?? 0) > 0,
        );

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
                  if (_refreshError != null) ...[
                    FxCard(
                      padding: const EdgeInsets.all(16),
                      expanded: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '近 30 天数据刷新未确认，以下仍为上次成功读取的统计。',
                            style: SlowlightTypography.secondary(context),
                          ),
                          const SizedBox(height: SlowlightSpacing.md),
                          FxButton(
                            label: '重新加载',
                            variant: FxButtonVariant.outline,
                            size: FxButtonSize.sm,
                            onPressed: _load,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _summaryCard(summary),
                  const SizedBox(height: 14),
                  if (_trendLoadFailed)
                    FxCard(
                      padding: const EdgeInsets.all(16),
                      expanded: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FxSectionHeader(title: '每日完成趋势'),
                          const SizedBox(height: 8),
                          Text(
                            '趋势暂时无法加载，已载入的任务统计仍可查看。',
                            style: SlowlightTypography.secondary(context),
                          ),
                          const SizedBox(height: 8),
                          FxButton(
                            label: '重新加载',
                            variant: FxButtonVariant.outline,
                            size: FxButtonSize.sm,
                            onPressed: _load,
                          ),
                        ],
                      ),
                    )
                  if (_trendDays.isNotEmpty) ...[
                    const SizedBox(height: SlowlightSpacing.md),
                    _trendCard(),
                  ] else if (!_trendLoadFailed && hasData)
                    _trendCard()
                  else if (!_trendLoadFailed)
                    const FxEmptyState(
                      icon: LucideIcons.calendarDays,
                      title: '近 30 天还没有任务记录',
                      subtitle: '有记录后，这里会展示完成趋势与任务分布。',
                      padding: EdgeInsets.symmetric(vertical: 24),
                    ),
                  if (hasData && dist.isNotEmpty) ...[
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
    final days = (summary['total_days'] as num?)?.toInt() ?? 30;
    final bestDay =
        summary['best_day'] is Map
            ? Map<String, dynamic>.from(summary['best_day'] as Map)
            : null;
    final bestCount = (bestDay?['completed'] as num?)?.toInt() ?? 0;
    final habitCount = _trendDays.fold<int>(
      0,
      (sum, day) => sum + ((day['habit_checked'] as num?)?.toInt() ?? 0),
    );

    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FxSectionHeader(title: '近 30 天已载入记录', trailing: '$days 天'),
          const SizedBox(height: 12),
          _stats([
            FxStatCell(value: '$completed', label: '完成任务'),
            FxStatCell(value: '$created', label: '新建任务'),
            FxStatCell(
              value: _trendDays.isEmpty ? '—' : '$habitCount',
              label: '习惯记录',
            ),
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
    return FxResponsiveFormGrid(
      minColumnWidth: 96,
      maxColumns: 3,
      horizontalGap: 8,
      verticalGap: 8,
      children: cells,
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
          const FxSectionHeader(title: '每日任务完成趋势', trailing: '近 30 天'),
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
    return SizedBox(
      height: 142,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (index) {
          final date = _trendDays[index]['date']?.toString() ?? '';
          final showLabel =
              index == 0 || index == values.length - 1 || index % 7 == 0;
          final label = date.length >= 10 ? date.substring(5) : date;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 7,
                        height:
                            values[index] == 0 ? 2 : 82 * values[index] / max,
                        decoration: BoxDecoration(
                          color: activePalette.accent.withValues(alpha: .78),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 22,
                    child:
                        showLabel
                            ? FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                style: SlowlightTypography.caption(
                                  context,
                                ).copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                            : const SizedBox.shrink(),
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
          FxSectionHeader(title: '最近完成任务', trailing: '${tasks.length} 条'),
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
          Text('近 30 天回顾加载失败', style: SlowlightTypography.cardTitle(context)),
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
