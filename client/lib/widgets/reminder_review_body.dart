import 'package:flutter/material.dart';

import '../services/reminder_local.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';

class ReminderReviewScreen extends StatelessWidget {
  const ReminderReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            FxPageHeader(
              title: '休息回顾',
              trailing: FxChip(
                label: '来自回顾 · 只读',
                backgroundColor: fxSubtleSurface(context),
                foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                borderRadius: 999,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              ),
            ),
            const Expanded(child: ReminderReviewBody()),
          ],
        ),
      ),
    );
  }
}

class ReminderReviewBody extends StatefulWidget {
  const ReminderReviewBody({super.key});

  @override
  State<ReminderReviewBody> createState() => _ReminderReviewBodyState();
}

class _ReminderReviewBodyState extends State<ReminderReviewBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _local = ReminderLocal();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: FxSegmented(
                labels: const ['日志', '7天', '30天', '分析'],
                selectedIndex: _tabs.index,
                onChanged: (index) => setState(() => _tabs.index = index),
                backgroundColor: fxSubtleSurface(context),
                selectedColor: fxSurface(context),
                borderRadius: AppTheme.radiusMd,
              ),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
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
  late String _date;
  List<Map<String, dynamic>> _sessions = const [];
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
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  void _move(int days) {
    final next = DateTime.parse(_date).add(Duration(days: days));
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final key = next.toIso8601String().substring(0, 10);
    if (key.compareTo(today) > 0) return;
    _date = key;
    _load();
  }

  String _time(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _duration(int seconds) {
    if (seconds <= 0) return '--';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}时${m}分';
    if (m > 0) return '${m}分${s}秒';
    return '${s}秒';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '前一天',
                onPressed: () => _move(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Flexible(
                child: Text(
                  _date,
                  style: SlowlightTypography.cardTitle(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '后一天',
                onPressed: _date == today ? null : () => _move(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: fxDivider(context)),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _sessions.isEmpty
                  ? FxEmptyState(
                      emoji: '☕',
                      title: '当天没有记录',
                      subtitle: '工作与休息记录会显示在这里',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _sessions.length,
                      itemBuilder: (context, index) {
                        final item = _sessions[index];
                        final type = item['type'] as String;
                        final skipped = (item['skipped'] as int?) == 1;
                        final work = type == 'work';
                        final color = work
                            ? AppTheme.primary
                            : skipped
                                ? theme.colorScheme.outline
                                : AppTheme.success;
                        final start = item['started_at'] as String?;
                        final end = item['ended_at'] as String?;
                        final period = start == null
                            ? '--'
                            : '${_time(start)} — ${end == null ? '进行中' : _time(end)}';
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: index.isEven
                                ? Colors.transparent
                                : theme.colorScheme.surfaceContainerLowest,
                            border: Border(
                              bottom: BorderSide(color: fxDivider(context)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                work
                                    ? Icons.work_outline
                                    : skipped
                                        ? Icons.skip_next_outlined
                                        : Icons.coffee_outlined,
                                color: color,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(period,
                                        style: SlowlightTypography.secondary(context)),
                                    Text(
                                      work ? '工作' : (skipped ? '跳过休息' : '有效休息'),
                                      style: SlowlightTypography.caption(context)
                                          .copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                skipped
                                    ? '已跳过'
                                    : _duration(
                                        (item['duration_seconds'] as int?) ?? 0),
                                style: SlowlightTypography.secondary(context)
                                    .copyWith(color: color),
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
  List<Map<String, dynamic>> _stats = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final stats = await widget.local.getDailyAggregatedStats(days: widget.days);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _loading = false;
    });
  }

  String _duration(int seconds) {
    if (seconds <= 0) return '0分';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}时${m}分' : '${m}分';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_stats.isEmpty) {
      return const FxEmptyState(
        emoji: '📊',
        title: '暂无数据',
        subtitle: '产生工作与休息记录后会形成统计',
      );
    }
    final work = _stats.fold<int>(
        0, (sum, row) => sum + ((row['work_seconds'] as int?) ?? 0));
    final workCount = _stats.fold<int>(
        0, (sum, row) => sum + ((row['work_count'] as int?) ?? 0));
    final rest = _stats.fold<int>(
        0, (sum, row) => sum + ((row['rest_seconds'] as int?) ?? 0));
    final restCount = _stats.fold<int>(
        0, (sum, row) => sum + ((row['rest_count'] as int?) ?? 0));
    final skip = _stats.fold<int>(
        0, (sum, row) => sum + ((row['skip_count'] as int?) ?? 0));
    final activeDays = _stats
        .where((row) => ((row['work_seconds'] as int?) ?? 0) > 0)
        .length;
    final reminders = restCount + skip;
    final skipRate = reminders == 0 ? 0 : (skip / reminders * 100).round();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FxCard(
          color: fxSurface(context),
          borderRadius: AppTheme.radiusLg,
          border: Border.all(color: fxBorder(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FxSectionHeader(title: '${widget.days}日汇总'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FxStatCell(value: '$workCount', label: '工作次数'),
                  FxStatCell(value: _duration(work), label: '累计工作'),
                  FxStatCell(value: '$restCount', label: '休息次数'),
                  FxStatCell(value: '$skipRate%', label: '跳过率'),
                ],
              ),
              if (activeDays > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '活跃 $activeDays 天 · 日均工作 ${_duration(work ~/ activeDays)} · 累计休息 ${_duration(rest)}',
                  style: SlowlightTypography.caption(context).copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const FxSectionHeader(title: '每日明细'),
        const SizedBox(height: 8),
        ..._stats.map((row) {
          final date = DateTime.tryParse(row['date']?.toString() ?? '');
          final label = date == null ? '${row['date'] ?? ''}' : '${date.month}/${date.day}';
          final seconds = (row['work_seconds'] as int?) ?? 0;
          final skips = (row['skip_count'] as int?) ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(width: 52, child: Text(label)),
                Expanded(
                  child: LinearProgressIndicator(
                    value: work == 0 ? 0 : (seconds / work).clamp(0, 1),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(width: 8),
                Text(_duration(seconds),
                    style: SlowlightTypography.caption(context)),
                if (skips > 0) ...[
                  const SizedBox(width: 8),
                  Text('跳过$skips',
                      style: SlowlightTypography.caption(context)),
                ],
              ],
            ),
          );
        }),
      ],
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
  Map<int, int> _hourly = const {};
  Map<String, dynamic> _weekday = const {};
  Map<String, dynamic> _bests = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      widget.local.getHourlyWorkDistribution(days: 30),
      widget.local.getWeekdayWeekendComparison(days: 30),
      widget.local.getPersonalBests(),
    ]);
    if (!mounted) return;
    setState(() {
      _hourly = results[0] as Map<int, int>;
      _weekday = results[1] as Map<String, dynamic>;
      _bests = results[2] as Map<String, dynamic>;
      _loading = false;
    });
  }

  String _duration(int seconds) {
    if (seconds <= 0) return '0分';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}时${m}分' : '${m}分';
  }

  Widget _card(Widget child) => FxCard(
        color: fxSurface(context),
        borderRadius: AppTheme.radiusLg,
        border: Border.all(color: fxBorder(context)),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final max = _hourly.values.isEmpty
        ? 1
        : _hourly.values.reduce((a, b) => a > b ? a : b);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const FxSectionHeader(title: '时段分布', trailing: '近 30 天'),
        const SizedBox(height: 8),
        _card(Column(
          children: List.generate(24, (hour) {
            final seconds = _hourly[hour] ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text('${hour.toString().padLeft(2, '0')}:00',
                        style: SlowlightTypography.caption(context)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: max == 0 ? 0 : seconds / max,
                      minHeight: 10,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 64,
                    child: Text(seconds == 0 ? '' : _duration(seconds),
                        style: SlowlightTypography.caption(context)),
                  ),
                ],
              ),
            );
          }),
        )),
        const SizedBox(height: 16),
        const FxSectionHeader(title: '工作日与周末', trailing: '近 30 天'),
        const SizedBox(height: 8),
        _card(Column(
          children: [
            _compare('工作日', '${_weekday['weekday_days'] ?? 0}天',
                _duration((_weekday['weekday_avg_work_seconds'] as int?) ?? 0),
                '${_weekday['weekday_avg_rest_count'] ?? 0}次'),
            Divider(color: fxDivider(context)),
            _compare('周末', '${_weekday['weekend_days'] ?? 0}天',
                _duration((_weekday['weekend_avg_work_seconds'] as int?) ?? 0),
                '${_weekday['weekend_avg_rest_count'] ?? 0}次'),
          ],
        )),
        const SizedBox(height: 16),
        const FxSectionHeader(title: '个人最佳'),
        const SizedBox(height: 8),
        _card(Column(
          children: [
            _best('最高单日工作', _bests['best_work_day'] == null
                ? '暂无'
                : '${_bests['best_work_day']} · ${_duration((_bests['best_work_seconds'] as int?) ?? 0)}'),
            _best('最长连续不跳过', ((_bests['longest_streak'] as int?) ?? 0) == 0
                ? '暂无'
                : '${_bests['longest_streak']}轮'),
            _best('最低跳过率日', _bests['best_skip_day'] == null
                ? '暂无'
                : '${_bests['best_skip_day']} · ${_bests['best_skip_rate'] ?? '0'}%'),
          ],
        )),
      ],
    );
  }

  Widget _compare(String label, String days, String work, String rest) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text('$label · $days',
                style: SlowlightTypography.secondary(context).copyWith(
                  fontWeight: FontWeight.w600,
                )),
            Text('日均工作 $work · 日均休息 $rest',
                style: SlowlightTypography.caption(context)),
          ],
        ),
      );

  Widget _best(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(label,
                style: SlowlightTypography.caption(context))),
            Flexible(child: Text(value,
                textAlign: TextAlign.right,
                style: SlowlightTypography.secondary(context).copyWith(
                  fontWeight: FontWeight.w500,
                ))),
          ],
        ),
      );
}
