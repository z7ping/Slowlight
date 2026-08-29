import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/high_fidelity/hf_page_header.dart';
import '../widgets/high_fidelity/high_fidelity_ui.dart';
import 'stats/stats_snapshot.dart';

class StatsScreen extends StatefulWidget {
  final bool embedded;

  const StatsScreen({super.key, this.embedded = false});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _loading = true;
  String? _error;
  StatsSnapshot? _snapshot;

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
      final data = await StatsSnapshot.load();
      if (!mounted) return;
      setState(() {
        _snapshot = data;
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
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? _errorView()
            : _content(_snapshot!);
    if (widget.embedded || !Navigator.of(context).canPop()) return body;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const HfPageHeader(title: '统计'),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _content(StatsSnapshot data) {
    final theme = Theme.of(context);
    final desktop = MediaQuery.sizeOf(context).width >= 1024;
    final last7 = data.last7Trend;
    final habitChecks = last7.fold<int>(
      0,
      (sum, row) => sum + ((row['habit_checked'] as num?)?.toInt() ?? 0),
    );
    final focusSeconds =
        (data.sessionStats['total_work_seconds'] as num?)?.toInt();
    final focusMinutes = focusSeconds == null
        ? (data.sessionStats['total_minutes'] as num?)?.toInt() ??
            data.todayFocusMinutes
        : focusSeconds ~/ 60;
    final observations = _observationCount(last7);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = desktop ? 4 : 2;
              final width =
                  (constraints.maxWidth - 12 * (columns - 1)) / columns;
              final cells = [
                HfStatCell(
                  value: '${data.completedThisWeek}',
                  label: '本周完成任务',
                ),
                HfStatCell(value: '$habitChecks', label: '习惯打卡次数'),
                HfStatCell(value: _focusText(focusMinutes), label: '专注总时长'),
                HfStatCell(
                  value: observations == null ? '—' : '$observations',
                  label: '写下观察',
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
              final chart = HfCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const HfSectionHeader(title: '每日专注时长', trailing: '分钟'),
                    const SizedBox(height: 18),
                    _bars(data),
                    const SizedBox(height: 10),
                    Text(
                      _factNote(data),
                      style: TextStyle(
                        fontSize: AppTheme.textXs,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
              final distribution = HfCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const HfSectionHeader(title: '时间分配', trailing: '近 7 天'),
                    const SizedBox(height: 12),
                    _timeDistribution(data),
                  ],
                ),
              );
              if (!desktop) {
                return Column(
                  children: [
                    chart,
                    const SizedBox(height: 14),
                    distribution,
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

  Widget _bars(StatsSnapshot data) {
    final points = data.last7Trend;
    if (points.isEmpty) {
      return const SizedBox(
        height: 132,
        child: Center(child: Text('暂无近 7 天数据')),
      );
    }
    final values = points.map((row) {
      return (row['focus_minutes'] as num?)?.toDouble() ??
          (row['focus_min'] as num?)?.toDouble() ??
          (row['task_completed'] as num?)?.toDouble() ??
          0;
    }).toList(growable: false);
    final max = values.fold<double>(1, (a, b) => b > a ? b : a);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (index) {
          final value = values[index];
          final date =
              DateTime.tryParse(points[index]['date']?.toString() ?? '');
          final label = date == null ? '' : weekdays[date.weekday - 1];
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
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
                            top: Radius.circular(AppTheme.radiusSm),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: AppTheme.textXs,
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
    if (raw is! List || raw.isEmpty) {
      return Text(
        '暂无时间分配数据',
        style: TextStyle(
          fontSize: AppTheme.textSm,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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
        final percent = ((item['percent'] as num?)?.toDouble() ?? 0)
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
                      style: const TextStyle(fontSize: AppTheme.textSm),
                    ),
                  ),
                  Text(
                    _focusText(minutes),
                    style: TextStyle(
                      fontSize: AppTheme.textXs,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                child: LinearProgressIndicator(
                  value: percent / 100,
                  minHeight: 7,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainer,
                  color: colors[index % colors.length],
                ),
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
    final points = data.last7Trend;
    if (points.isEmpty) return '↳ 暂无足够数据形成近 7 天事实';
    var bestIndex = 0;
    var best = -1;
    for (var i = 0; i < points.length; i++) {
      final value = (points[i]['focus_minutes'] as num?)?.toInt() ??
          (points[i]['task_completed'] as num?)?.toInt() ??
          0;
      if (value > best) {
        best = value;
        bestIndex = i;
      }
    }
    final date = DateTime.tryParse(points[bestIndex]['date']?.toString() ?? '');
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return date == null
        ? '↳ 近 7 天数据已更新'
        : '↳ ${weekdays[date.weekday - 1]}是本周期记录高峰';
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.chartNoAxesColumn, size: 24),
          const SizedBox(height: 8),
          const Text('统计数据加载失败'),
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
