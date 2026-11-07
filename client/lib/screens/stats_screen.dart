import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../ui/fx.dart';
import 'stats/stats_snapshot.dart';

class StatsScreen extends StatefulWidget {
  final bool embedded;
  /// Test seam; the real screen continues to use StatsSnapshot.load.
  final Future<StatsSnapshot> Function()? snapshotLoader;

  const StatsScreen({
    super.key,
    this.embedded = false,
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
    final last7 = data.last7Trend;
    final habitChecks = last7.fold<int>(
      0,
      (sum, row) => sum + ((row['habit_checked'] as num?)?.toInt() ?? 0),
    );
    final focusSeconds =
        (data.sessionStats['total_work_seconds'] as num?)?.toInt();
    final focusMinutes = focusSeconds == null
        ? (data.sessionStats['total_minutes'] as num?)?.toInt()
        : focusSeconds ~/ 60;
    final observations = _observationCount(last7);

    return FxRefresh(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
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
              final cells = [
                FxStatCell(
                  value: data.hasSource('daily_trend')
                      ? '${data.completedThisWeek}' : '—',
                  label: '本周完成任务',
                ),
                FxStatCell(
                  value: data.hasSource('daily_trend') ? '$habitChecks' : '—',
                  label: '习惯打卡次数',
                ),
                FxStatCell(
                  value: data.hasSource('session_stats') && focusMinutes != null
                      ? _focusText(focusMinutes) : '—',
                  label: '专注总时长',
                ),
                FxStatCell(
                  value: observations == null ? '—' : '$observations',
                  label: '记录观察',
                ),
              ];
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: cells
                    .map((cell) => SizedBox(width: width, child: cell))
                    .toList(growable: false),
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
                    _bars(data),
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
                  ],
                ),
              );
              if (!desktop) {
                return Column(
                  children: [chart, const SizedBox(height: 14), distribution],
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

  int? _observationCount(List<Map<String, dynamic>> rows) {
    var seen = false;
    var sum = 0;
    for (final row in rows) {
      final raw = row['reflection_count'] ?? row['observation_count'];
      if (raw is num) {
        seen = true;
        sum += raw.toInt();
      }
    }
    return seen ? sum : null;
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
