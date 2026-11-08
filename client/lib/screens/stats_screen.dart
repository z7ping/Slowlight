import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../ui/fx.dart';
import 'stats/stats_snapshot.dart';

/// Targets mirror the established mobile prototype's KPI actions.
enum StatsDestination { tasks, habits, focus, review, timeDistribution }

class StatsScreen extends StatefulWidget {
  final bool embedded;
  final ValueChanged<StatsDestination>? onNavigate;
  /// Test seam; the real screen continues to use StatsSnapshot.load.
  final Future<StatsSnapshot> Function()? snapshotLoader;

  const StatsScreen({
    super.key,
    this.embedded = false,
    this.onNavigate,
    this.snapshotLoader,
  });

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _loading = true;
  String? _error;
  StatsSnapshot? _snapshot;
  int _loadVersion = 0;
  int _periodDays = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() {
      _loading = _snapshot == null;
      _error = null;
    });
    try {
      final data = await (widget.snapshotLoader ?? StatsSnapshot.load)();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _snapshot = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        // A failed refresh cannot erase already-confirmed facts.
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _snapshot != null
        ? _content(_snapshot!)
        : _loading
            ? const Center(child: FxCircularProgress())
            : _errorView();
    if (widget.embedded || !Navigator.of(context).canPop()) return body;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [const FxPageHeader(title: '统计'), Expanded(child: body)],
        ),
      ),
    );
  }

  Widget _content(StatsSnapshot data) {
    final theme = Theme.of(context);
    final desktop = ResponsiveLayout.isDesktopOrWider(context);
    // Android has the prototype's Today / last-7-calendar-days switch.
    // Windows retains the established 7-day compact dashboard.
    final days = desktop ? 7 : _periodDays;
    final completed = data.countInDays('task_completed', days);
    final habitChecks = data.countInDays('habit_checked', days);
    final focusMinutes = data.focusMinutesInDays(days);
    final observations = data.observationCountInDays(days);

    return FxRefresh(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          if (!desktop) ...[
            Text('记录概况', style: SlowlightTypography.cardTitle(context)),
            const SizedBox(height: 10),
            FxSegmented(
              labels: const ['近 7 天', '今天'],
              selectedIndex: _periodDays == 7 ? 0 : 1,
              onChanged: (index) => setState(
                () => _periodDays = index == 0 ? 7 : 1,
              ),
              expanded: true,
            ),
            const SizedBox(height: 12),
          ],
          if (_error != null || data.unavailableSources.isNotEmpty) ...[
            FxCard(
              padding: const EdgeInsets.all(12),
              expanded: true,
              child: Row(
                children: [
                  const Icon(LucideIcons.triangleAlert, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error != null
                          ? '刷新未确认，以下仍是上次已确认的数据。'
                          : '部分统计来源未读取，未确认的数据以「—」表示。',
                      style: SlowlightTypography.secondary(context),
                    ),
                  ),
                  FxButton(
                    label: '重试',
                    variant: FxButtonVariant.ghost,
                    size: FxButtonSize.sm,
                    onPressed: _load,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final minCellWidth =
                  (140 + (textScale - 1) * 40).clamp(140, 180).toDouble();
              var columns = desktop ? 4 : 2;
              double cellWidth(int count) =>
                  (constraints.maxWidth - 12 * (count - 1)) / count;
              if (columns == 4 && cellWidth(4) < minCellWidth) columns = 2;
              if (columns == 2 && cellWidth(2) < minCellWidth) columns = 1;

              final width = cellWidth(columns);
              final cells = <({StatsDestination target, FxStatCell cell})>[
                (
                  target: StatsDestination.tasks,
                  cell: FxStatCell(
                    value: completed?.toString() ?? '—',
                    label: desktop ? '本周完成任务' : '完成任务',
                  ),
                ),
                (
                  target: StatsDestination.habits,
                  cell: FxStatCell(
                    value: habitChecks?.toString() ?? '—',
                    label: desktop ? '习惯打卡次数' : '习惯记录',
                  ),
                ),
                (
                  target: StatsDestination.focus,
                  cell: FxStatCell(
                    value: focusMinutes == null ? '—' : _focusText(focusMinutes),
                    label: desktop ? '专注总时长'
                        : days == 7 ? '近 7 天专注' : '今日专注',
                  ),
                ),
                (
                  target: StatsDestination.review,
                  cell: FxStatCell(
                    value: observations?.toString() ?? '—',
                    label: desktop ? '记录观察' : '观察记录',
                  ),
                ),
              ];
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: cells.map((item) {
                  final cell = widget.onNavigate == null
                      ? item.cell
                      : FxInkWell(
                          key: ValueKey('stats.kpi.${item.target.name}'),
                          borderRadius:
                              BorderRadius.circular(SlowlightRadius.lg),
                          onTap: () => widget.onNavigate!(item.target),
                          child: Semantics(
                            button: true,
                            child: item.cell,
                          ),
                        );
                  return SizedBox(width: width, child: cell);
                }).toList(growable: false),
              );
            },
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final chart = FxCard(
                padding: const EdgeInsets.all(16),
                expanded: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FxSectionHeader(title: '每日专注时长', trailing: '分钟'),
                    const SizedBox(height: 18),
                    desktop ? _bars(data) : _focusHistory(data),
                    const SizedBox(height: 10),
                    Text(
                      _factNote(data),
                      style: SlowlightTypography.caption(
                        context,
                      ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              );
              final distribution = FxCard(
                padding: const EdgeInsets.all(16),
                expanded: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FxSectionHeader(title: '时间分配', trailing: '近 7 天'),
                    const SizedBox(height: 12),
                    _timeDistribution(data),
                    if (widget.onNavigate != null) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FxButton(
                          label: '查看详细时间分配',
                          variant: FxButtonVariant.link,
                          size: FxButtonSize.sm,
                          onPressed: () => widget.onNavigate!(
                            StatsDestination.timeDistribution,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
              if (!desktop) {
                return Column(
                  children: [
                    chart,
                    const SizedBox(height: 14),
                    distribution,
                    const SizedBox(height: 14),
                    FxCard(
                      padding: const EdgeInsets.all(16),
                      expanded: true,
                      child: _recordFacts(data, days),
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 13, child: chart),
                  const SizedBox(width: 16),
                  Expanded(flex: 10, child: distribution),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _focusHistory(StatsSnapshot data) {
    final points = data.focusLast7;
    if (!data.hasSource('session_stats') || points.isEmpty) {
      return const SizedBox(
        height: 132,
        child: Center(child: Text('近 7 天专注记录暂不可用')),
      );
    }
    final maximum = points.fold<int>(
      1, (value, point) => point.minutes > value ? point.minutes : value,
    );
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Column(
      children: points.map((point) {
        final day = point.day;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 82,
                child: Text(
                  '${day.month}/${day.day} · 周${weekdays[day.weekday - 1]}',
                  style: SlowlightTypography.caption(context),
                ),
              ),
              Expanded(
                child: FxProgress(
                  value: point.minutes / maximum,
                  height: 7,
                  color: AppTheme.chartBlue,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 48,
                child: Text(
                  '${point.minutes} 分',
                  textAlign: TextAlign.end,
                  style: SlowlightTypography.caption(context),
                ),
              ),
            ],
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _recordFacts(StatsSnapshot data, int days) {
    final now = DateTime.now();
    final dates = List.generate(days, (index) =>
        DateTime(now.year, now.month, now.day - days + index + 1));
    final hasObservations = dates.every((day) =>
        data.countOn(day, 'reflection_count') != null ||
        data.countOn(day, 'observation_count') != null);
    final values = dates.map((day) {
      final tasks = data.countOn(day, 'task_completed');
      final habits = data.countOn(day, 'habit_checked');
      if (tasks == null || habits == null) return null;
      final observations = hasObservations
          ? (data.countOn(day, 'reflection_count') ??
              data.countOn(day, 'observation_count')!)
          : 0;
      return tasks + habits + observations;
    }).toList(growable: false);
    final known = values.whereType<int>().toList(growable: false);
    final maximum = known.fold<int>(1,
        (largest, current) => current > largest ? current : largest);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FxSectionHeader(
          title: hasObservations ? '记录事实' : '任务与习惯记录',
          trailing: days == 7 ? '近 7 天' : '今天',
        ),
        const SizedBox(height: 12),
        if (known.isEmpty)
          Text('记录来源暂不可用',
              style: SlowlightTypography.secondary(context))
        else if (known.every((value) => value == 0))
          Text('这段时间还没有记录',
              style: SlowlightTypography.secondary(context))
        else
          ...List.generate(dates.length, (index) {
            final day = dates[index];
            final count = values[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 82,
                    child: Text(
                      '${day.month}/${day.day} · 周${weekdays[day.weekday - 1]}',
                      style: SlowlightTypography.caption(context),
                    ),
                  ),
                  Expanded(
                    child: count == null
                        ? const SizedBox(height: 7)
                        : FxProgress(
                            value: count / maximum,
                            height: 7,
                            color: AppTheme.chartBlue,
                          ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 32,
                    child: Text(
                      count?.toString() ?? '—',
                      textAlign: TextAlign.end,
                      style: SlowlightTypography.caption(context),
                    ),
                  ),
                ],
              ),
            );
          }),
        if (!hasObservations) ...[
          const SizedBox(height: 8),
          Text(
            '观察数量未纳入趋势（当前来源未提供每日观察事实）',
            style: SlowlightTypography.caption(context),
          ),
        ],
      ],
    );
  }

  Widget _bars(StatsSnapshot data) {
    final points = data.focusLast7;
    if (!data.hasSource('session_stats') || points.isEmpty) {
      return const SizedBox(
        height: 132,
        child: Center(child: Text('近 7 天专注记录暂不可用')),
      );
    }
    final values = points
        .map((row) => row.minutes.toDouble())
        .toList(growable: false);
    final max = values.fold<double>(1, (a, b) => b > a ? b : a);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return SizedBox(
      height: 166,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (index) {
          final value = values[index];
          final label = weekdays[points[index].day.weekday - 1];
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 20,
                        height: value <= 0 ? 4 : 108 * value / max,
                        decoration: BoxDecoration(
                          color: AppTheme.chartBlue.withValues(
                            alpha: index == values.length - 2 ? .48 : .88,
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(SlowlightRadius.sm),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: SlowlightTypography.caption(context).copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _timeDistribution(StatsSnapshot data) {
    final raw = data.timeDistribution['tags'];
    if (!data.hasSource('time_distribution') || raw is! List || raw.isEmpty) {
      return Text(
        data.hasSource('time_distribution')
            ? '暂无时间分配数据' : '时间分配暂不可用',
        style: SlowlightTypography.secondary(
          context,
        ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    final items = raw
        .take(4)
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList(growable: false);
    final colors = [
      AppTheme.chartPurple,
      AppTheme.chartBlue,
      AppTheme.chartGreen,
      AppTheme.chartYellow,
    ];
    return Column(
      children: List.generate(items.length, (index) {
        final item = items[index];
        final percent =
            ((item['percent'] as num?)?.toDouble() ?? 0)
                .clamp(0, 100)
                .toDouble();
        final minutes = (item['total_min'] as num?)?.toInt() ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item['icon'] ?? ''} ${item['name'] ?? ''}'.trim(),
                      style: SlowlightTypography.secondary(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _focusText(minutes),
                      textAlign: TextAlign.end,
                      style: SlowlightTypography.caption(context).copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              FxProgress(
                value: percent / 100,
                height: 7,
                color: colors[index % colors.length],
              ),
            ],
          ),
        );
      }),
    );
  }

  String _focusText(int minutes) {
    if (minutes < 60) return '$minutes 分';
    final hours = minutes / 60;
    final value = hours.toStringAsFixed(hours == hours.roundToDouble() ? 0 : 1);
    return '$value 小时';
  }

  String _factNote(StatsSnapshot data) {
    final points = data.focusLast7;
    if (!data.hasSource('session_stats') || points.isEmpty) {
      return '↳ 专注事实尚未确认，不使用任务数代替专注时长';
    }
    var best = points.first;
    for (final point in points.skip(1)) {
      if (point.minutes > best.minutes) best = point;
    }
    if (best.minutes == 0) return '↳ 近 7 天没有已记录的专注时长';
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '↳ ${weekdays[best.day.weekday - 1]}专注最多：${best.minutes} 分钟';
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.chartNoAxesColumn, size: 24),
          const SizedBox(height: 8),
          Text('统计数据加载失败', style: SlowlightTypography.cardTitle(context)),
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
