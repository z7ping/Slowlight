import 'package:flutter/material.dart';

import '../services/reminder_local.dart';
import '../theme/app_theme.dart';
import 'high_fidelity/hf_page_header.dart';
import 'high_fidelity/high_fidelity_ui.dart';

/// 休息提醒回顾页面。按照高保真原型作为 L2 推送页展示。
class ReminderReviewScreen extends StatelessWidget {
  const ReminderReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const HfPageHeader(
              title: '休息回顾',
              trailing: HfChip('来自回顾 · 只读'),
            ),
            const Expanded(child: ReminderReviewBody()),
          ],
        ),
      ),
    );
  }
}

/// 休息回顾主体组件（可嵌入到其他页面）。
class ReminderReviewBody extends StatefulWidget {
  const ReminderReviewBody({super.key});

  @override
  State<ReminderReviewBody> createState() => _ReminderReviewBodyState();
}

class _ReminderReviewBodyState extends State<ReminderReviewBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _local = ReminderLocal();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (_tabController.index == index) return;
    setState(() => _tabController.index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: HfSegmented(
              labels: const ['日志', '7天', '30天', '分析'],
              selectedIndex: _tabController.index,
              onChanged: _selectTab,
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _LogTab(local: _local),
              _RangeStatsTab(local: _local, days: 7),
              _RangeStatsTab(local: _local, days: 30),
              _AnalysisTab(local: _local),
            ],
          ),
        ),
      ],
    );
  }
}

class _LogTab extends StatefulWidget {
  final ReminderLocal local;
  const _LogTab({required this.local});

  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> {
  String _date = '';
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now().toIso8601String().substring(0, 10);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sessions = await widget.local.getDateSessions(_date);
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    }
  }

  void _prevDay() {
    final dt = DateTime.parse(_date).subtract(const Duration(days: 1));
    _date = dt.toIso8601String().substring(0, 10);
    _load();
  }

  void _nextDay() {
    final dt = DateTime.parse(_date).add(const Duration(days: 1));
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (dt.toIso8601String().substring(0, 10).compareTo(today) <= 0) {
      _date = dt.toIso8601String().substring(0, 10);
      _load();
    }
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}';
    } catch (_) {
      return '--:--';
    }
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '--';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}时${m}分';
    if (m > 0) return '${m}分${s}秒';
    return '${s}秒';
  }

  String _periodLabel(String? startedAt, String? endedAt) {
    if (startedAt == null) return '--';
    final start = _formatTime(startedAt);
    if (endedAt == null) return '$start — 进行中';
    return '$start — ${_formatTime(endedAt)}';
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final isToday = _date == today;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: _prevDay,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
              Text(
                _date,
                style: TextStyle(
                  fontSize: AppTheme.textMd,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: isToday ? null : _nextDay,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _sessions.isEmpty
                  ? Center(
                      child: Text(
                        '当天没有记录',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _sessions.length,
                      separatorBuilder: (_, __) => const SizedBox.shrink(),
                      itemBuilder: (context, index) {
                        final s = _sessions[index];
                        final type = s['type'] as String;
                        final skipped = (s['skipped'] as int?) == 1;
                        final isWork = type == 'work';

                        Color dotColor;
                        IconData leadingIcon;
                        if (isWork) {
                          dotColor = AppTheme.primary;
                          leadingIcon = Icons.work_outline;
                        } else if (skipped) {
                          dotColor = Theme.of(context).colorScheme.outline;
                          leadingIcon = Icons.skip_next_outlined;
                        } else {
                          dotColor = AppTheme.success;
                          leadingIcon = Icons.coffee_outlined;
                        }

                        final durationStr = skipped
                            ? '已跳过'
                            : _formatDuration((s['duration_seconds'] as int?) ?? 0);

                        return Container(
                          color: index.isEven
                              ? Colors.transparent
                              : Theme.of(context).colorScheme.surfaceContainerLowest,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: dotColor.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(leadingIcon, size: 16, color: dotColor),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _periodLabel(
                                        s['started_at'] as String?,
                                        s['ended_at'] as String?,
                                      ),
                                      style: TextStyle(
                                        fontSize: AppTheme.textSm,
                                        color: Theme.of(context).colorScheme.onSurface,
                                        decoration: skipped ? TextDecoration.lineThrough : null,
                                      ),
                                    ),
                                    Text(
                                      isWork ? '工作' : (skipped ? '跳过休息' : '有效休息'),
                                      style: TextStyle(
                                        fontSize: AppTheme.textXs,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                durationStr,
                                style: TextStyle(
                                  fontSize: AppTheme.textSm,
                                  fontWeight: FontWeight.w500,
                                  color: skipped
                                      ? Theme.of(context).colorScheme.onSurfaceVariant
                                      : dotColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _RangeStatsTab extends StatefulWidget {
  final ReminderLocal local;
  final int days;
  const _RangeStatsTab({required this.local, required this.days});

  @override
  State<_RangeStatsTab> createState() => _RangeStatsTabState();
}

class _RangeStatsTabState extends State<_RangeStatsTab> {
  List<Map<String, dynamic>> _dailyStats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final stats = await widget.local.getDailyAggregatedStats(days: widget.days);
    if (mounted) {
      setState(() {
        _dailyStats = stats;
        _loading = false;
      });
    }
  }

  String _fmtDur(int seconds) {
    if (seconds <= 0) return '0';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}时${m}分';
    return '${m}分';
  }

  String _fmtDate(String date) {
    try {
      final dt = DateTime.parse(date);
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return date;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_dailyStats.isEmpty) {
      return Center(
        child: Text(
          '暂无数据',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    int totalWork = 0;
    int totalWorkCount = 0;
    int totalRest = 0;
    int totalRestCount = 0;
    int totalSkip = 0;
    for (final d in _dailyStats) {
      totalWork += (d['work_seconds'] as int?) ?? 0;
      totalWorkCount += (d['work_count'] as int?) ?? 0;
      totalRest += (d['rest_seconds'] as int?) ?? 0;
      totalRestCount += (d['rest_count'] as int?) ?? 0;
      totalSkip += (d['skip_count'] as int?) ?? 0;
    }
    final activeDays = _dailyStats
        .where((d) => ((d['work_seconds'] as int?) ?? 0) > 0)
        .length;
    final totalReminders = totalRestCount + totalSkip;
    final avgSkipRate =
        totalReminders > 0 ? (totalSkip / totalReminders * 100).round() : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HfCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.days}日汇总',
                  style: TextStyle(
                    fontSize: AppTheme.textMd,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                _summaryRow('累计工作', '$totalWorkCount次 · ${_fmtDur(totalWork)}'),
                _summaryRow('累计休息', '$totalRestCount次 · ${_fmtDur(totalRest)}'),
                _summaryRow('跳过次数', '$totalSkip次 · 跳过率$avgSkipRate%'),
                _summaryRow('活跃天数', '$activeDays天'),
                if (activeDays > 0)
                  _summaryRow('日均工作', _fmtDur(totalWork ~/ activeDays)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '每日明细',
            style: TextStyle(
              fontSize: AppTheme.textMd,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          ..._dailyStats.map((d) {
            final date = _fmtDate(d['date'] as String);
            final workS = (d['work_seconds'] as int?) ?? 0;
            final skips = (d['skip_count'] as int?) ?? 0;
            final maxWork = _dailyStats.fold<int>(0, (max, item) {
              final work = (item['work_seconds'] as int?) ?? 0;
              return work > max ? work : max;
            });
            final barWidth = maxWork > 0
                ? (workS / maxWork * 120).clamp(4.0, 120.0)
                : 0.0;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      date,
                      style: TextStyle(
                        fontSize: AppTheme.textXs,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: barWidth,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _fmtDur(workS),
                      style: TextStyle(
                        fontSize: AppTheme.textXs,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (skips > 0)
                    Text(
                      '跳过$skips',
                      style: TextStyle(
                        fontSize: AppTheme.textXs,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: AppTheme.textSm,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: AppTheme.textSm,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisTab extends StatefulWidget {
  final ReminderLocal local;
  const _AnalysisTab({required this.local});

  @override
  State<_AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends State<_AnalysisTab> {
  Map<int, int> _hourlyData = {};
  Map<String, dynamic> _weekdayData = {};
  Map<String, dynamic> _bests = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      widget.local.getHourlyWorkDistribution(days: 30),
      widget.local.getWeekdayWeekendComparison(days: 30),
      widget.local.getPersonalBests(),
    ]);
    if (mounted) {
      setState(() {
        _hourlyData = results[0] as Map<int, int>;
        _weekdayData = results[1] as Map<String, dynamic>;
        _bests = results[2] as Map<String, dynamic>;
        _loading = false;
      });
    }
  }

  String _fmtDur(int seconds) {
    if (seconds <= 0) return '0';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}时${m}分';
    return '${m}分钟';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final maxHourly = _hourlyData.values.isEmpty
        ? 1
        : _hourlyData.values.fold<int>(0, (a, b) => a > b ? a : b);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('时段分布（近30天）'),
          const SizedBox(height: 8),
          HfCard(
            child: Column(
              children: List.generate(24, (hour) {
                final seconds = _hourlyData[hour] ?? 0;
                final ratio = maxHourly > 0 ? seconds / maxHourly : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Text(
                          '${hour.toString().padLeft(2, "0")}:00',
                          style: TextStyle(
                            fontSize: AppTheme.textXs,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                            color: ratio > 0
                                ? AppTheme.primary.withValues(alpha: 0.15 + ratio * 0.6)
                                : Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 48,
                        child: Text(
                          seconds > 0 ? _fmtDur(seconds) : '',
                          style: TextStyle(
                            fontSize: AppTheme.textXs,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('工作日与周末（近30天）'),
          const SizedBox(height: 8),
          HfCard(
            child: Column(
              children: [
                _compareRow(
                  '工作日',
                  '${_weekdayData['weekday_days'] ?? 0}天',
                  _fmtDur((_weekdayData['weekday_avg_work_seconds'] as int?) ?? 0),
                  '${_weekdayData['weekday_avg_rest_count'] ?? 0}次',
                  AppTheme.primary,
                ),
                const Divider(height: 16),
                _compareRow(
                  '周末',
                  '${_weekdayData['weekend_days'] ?? 0}天',
                  _fmtDur((_weekdayData['weekend_avg_work_seconds'] as int?) ?? 0),
                  '${_weekdayData['weekend_avg_rest_count'] ?? 0}次',
                  AppTheme.warning,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('个人最佳'),
          const SizedBox(height: 8),
          HfCard(
            child: Column(
              children: [
                _bestRow(
                  Icons.emoji_events,
                  '最高单日工作',
                  _bests['best_work_day'] != null
                      ? '${_bests['best_work_day']} · ${_fmtDur((_bests['best_work_seconds'] as int?) ?? 0)}'
                      : '暂无',
                  AppTheme.warning,
                ),
                const SizedBox(height: 10),
                _bestRow(
                  Icons.straighten,
                  '最长连续不跳过',
                  ((_bests['longest_streak'] as int?) ?? 0) > 0
                      ? '${_bests['longest_streak']}轮${_bests['streak_date'] != null ? ' · 自 ${_bests['streak_date']}' : ''}'
                      : '暂无',
                  AppTheme.success,
                ),
                const SizedBox(height: 10),
                _bestRow(
                  Icons.thumb_up_alt_outlined,
                  '最低跳过率日',
                  _bests['best_skip_day'] != null
                      ? '${_bests['best_skip_day']} · ${_bests['best_skip_rate'] ?? "0"}%'
                      : '暂无',
                  AppTheme.info,
                ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: AppTheme.textMd,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  Widget _compareRow(
    String label,
    String days,
    String avgWork,
    String avgRest,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: AppTheme.textSm,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Text(
              days,
              style: TextStyle(
                fontSize: AppTheme.textXs,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const Spacer(),
        Text(
          '日均工作 $avgWork',
          style: TextStyle(
            fontSize: AppTheme.textXs,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '日均休息 $avgRest',
          style: TextStyle(
            fontSize: AppTheme.textXs,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _bestRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: AppTheme.textXs,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: AppTheme.textSm,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
