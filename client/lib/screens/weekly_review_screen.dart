import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../ai/ai_service.dart';
import '../services/api/analytics_api.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/high_fidelity/high_fidelity_ui.dart';

/// 每周回顾：作为「更多工具」内容页嵌入主壳。
class WeeklyReviewScreen extends StatefulWidget {
  const WeeklyReviewScreen({super.key});

  @override
  State<WeeklyReviewScreen> createState() => _WeeklyReviewScreenState();
}

class _WeeklyReviewScreenState extends State<WeeklyReviewScreen> {
  bool _loading = true;
  bool _generatingAi = false;
  String? _loadError;
  String? _aiReport;
  Map<String, dynamic> _review = {};
  Map<String, dynamic> _outputStats = {};
  List<Map<String, dynamic>> _dailyTrend = const [];

  @override
  void initState() {
    super.initState();
    _loadReview();
  }

  Future<void> _loadReview() async {
    if (mounted)
      setState(() {
        _loading = true;
        _loadError = null;
      });
    try {
      final results = await Future.wait<dynamic>([
        AnalyticsApi.getWeeklyReview(),
        AnalyticsApi.getOutputStats(period: 'week')
            .catchError((_) => <String, dynamic>{}),
        AnalyticsApi.getDailyTrend(days: 7)
            .catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _review = results[0] as Map<String, dynamic>;
        _outputStats = results[1] as Map<String, dynamic>;
        _dailyTrend = results[2] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e.toString();
        });
      }
    }
  }

  Future<void> _generateAiReport() async {
    if (_generatingAi) return;
    setState(() => _generatingAi = true);
    try {
      final ai = AiService();
      if (!await ai.isEnabled()) {
        _message('请先在设置中启用 AI 服务');
        return;
      }
      final text = await ai.reflectOnReview({
        'facts': _review,
        'patterns': {
          'period': 'week',
          'output_stats': _outputStats,
          'daily_trend': _dailyTrend,
        },
      });
      if (!mounted) return;
      setState(() => _aiReport = text.trim());
    } catch (e) {
      _message('AI 周报生成失败：$e');
    } finally {
      if (mounted) setState(() => _generatingAi = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.triangleAlert, size: 24),
            const SizedBox(height: 8),
            const Text('每周回顾加载失败'),
            const SizedBox(height: 4),
            Text(
              '请检查网络或数据服务后重试',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FxButton(
              label: '重试',
              variant: FxButtonVariant.secondary,
              onPressed: _loadReview,
            ),
          ],
        ),
      );
    }
    final theme = Theme.of(context);
    final weekStart = _review['week_start']?.toString() ?? '';
    final weekEnd = _review['week_end']?.toString() ?? '';

    return RefreshIndicator(
      onRefresh: _loadReview,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 72),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '每周回顾',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              weekStart.isEmpty
                                  ? '回看这一周真实发生的变化'
                                  : '$weekStart — $weekEnd · 回看真实发生的变化',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: IconButton(
                          tooltip: '刷新',
                          onPressed: _loadReview,
                          icon: const Icon(LucideIcons.refreshCw, size: 17),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _summary(),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 700;
                      final comparison = _comparison();
                      final distribution = _distribution();
                      if (!wide) {
                        return Column(
                          children: [
                            comparison,
                            const SizedBox(height: 14),
                            distribution,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: comparison),
                          const SizedBox(width: 14),
                          Expanded(child: distribution),
                        ],
                      );
                    },
                  ),
                  if ((_aiReport ?? '').isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _aiReportCard(),
                  ],
                  if (_hasOutputData) ...[
                    const SizedBox(height: 14),
                    _outputCard(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    final habitChecked = (_review['habit_checked'] as num?)?.toInt() ?? 0;
    final taskCompleted = (_review['task_completed'] as num?)?.toInt() ?? 0;
    final focusMinutes = (_review['focus_minutes'] as num?)?.toInt() ?? 0;
    return HfCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HfSectionHeader(title: '本周记录'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: HfStatCell(
                  value: '$habitChecked',
                  label: '习惯打卡',
                  suffix: ' 次',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: HfStatCell(
                  value: '$taskCompleted',
                  label: '完成任务',
                  suffix: ' 个',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: HfStatCell(
                  value: '$focusMinutes',
                  label: '专注',
                  suffix: ' 分钟',
                ),
              ),
            ],
          ),
          if (_dailyTrend.isNotEmpty) ...[
            const SizedBox(height: 14),
            _weeklyBars(),
          ],
        ],
      ),
    );
  }

  Widget _weeklyBars() {
    final theme = Theme.of(context);
    final values = _dailyTrend.map((item) {
      final tasks = (item['task_completed'] as num?)?.toInt() ?? 0;
      final habits = (item['habit_checked'] as num?)?.toInt() ?? 0;
      return tasks + habits;
    }).toList(growable: false);
    final max = values.fold<int>(1, (a, b) => b > a ? b : a);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '每日记录',
          style: TextStyle(
            fontSize: AppTheme.textXs,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 82,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(_dailyTrend.length, (index) {
              final value = values[index];
              final date = DateTime.tryParse(
                _dailyTrend[index]['date']?.toString() ?? '',
              );
              final label = date == null ? '' : weekdays[date.weekday - 1];
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: 18,
                            height: value <= 0 ? 3 : 54 * value / max,
                            decoration: BoxDecoration(
                              color:
                                  activePalette.accent.withValues(alpha: .82),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(AppTheme.radiusSm),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: AppTheme.textXs,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _comparison() {
    final theme = Theme.of(context);
    final habitDelta = ((_review['habit_checked'] as num?)?.toInt() ?? 0) -
        ((_review['habit_last_week'] as num?)?.toInt() ?? 0);
    final taskDelta = ((_review['task_completed'] as num?)?.toInt() ?? 0) -
        ((_review['task_last_week'] as num?)?.toInt() ?? 0);
    final focusDelta = ((_review['focus_minutes'] as num?)?.toInt() ?? 0) -
        ((_review['focus_last_week'] as num?)?.toInt() ?? 0);
    final hasData = (_review['habit_last_week'] ?? 0) != 0 ||
        (_review['task_last_week'] ?? 0) != 0 ||
        (_review['focus_last_week'] ?? 0) != 0;

    return HfCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HfSectionHeader(title: '和上周比'),
          const SizedBox(height: 10),
          if (!hasData)
            Text(
              '数据积累中，下周会有可对比记录。',
              style: TextStyle(
                fontSize: AppTheme.textSm,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            _deltaRow('习惯打卡', habitDelta, '次'),
            _deltaRow('完成任务', taskDelta, '个'),
            _deltaRow('专注时长', focusDelta, '分钟'),
          ],
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: _generatingAi ? null : _generateAiReport,
            child: SizedBox(
              height: 44,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: activePalette.accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _generatingAi ? '正在生成 AI 周报…' : '生成 AI 周报 →',
                    style: TextStyle(
                      fontSize: AppTheme.textXs,
                      fontWeight: FontWeight.w600,
                      color: activePalette.accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deltaRow(String label, int delta, String unit) {
    final theme = Theme.of(context);
    final positive = delta > 0;
    final zero = delta == 0;
    final color = zero
        ? theme.colorScheme.onSurfaceVariant
        : positive
            ? AppTheme.success
            : AppTheme.warning;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: hfDivider(context))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Icon(
            zero
                ? LucideIcons.minus
                : positive
                    ? LucideIcons.arrowUp
                    : LucideIcons.arrowDown,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '${delta > 0 ? '+' : ''}$delta $unit',
            style: TextStyle(
              fontSize: AppTheme.textXs,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _distribution() {
    final theme = Theme.of(context);
    final tags = (_review['time_distribution'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    tags.sort(
      (a, b) => ((b['total_min'] as num?)?.toInt() ?? 0)
          .compareTo((a['total_min'] as num?)?.toInt() ?? 0),
    );

    return HfCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HfSectionHeader(title: '时间分布'),
          const SizedBox(height: 10),
          if (tags.isEmpty)
            Text(
              '本周还没有足够的专注分布数据。',
              style: TextStyle(
                fontSize: AppTheme.textSm,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...tags.take(6).map((tag) {
              final name = tag['name']?.toString() ?? '未分类';
              final minutes = (tag['total_min'] as num?)?.toInt() ?? 0;
              final percent = (tag['percent'] as num?)?.toDouble() ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '$minutes 分钟 · ${percent.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: AppTheme.textXs,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      child: LinearProgressIndicator(
                        value: (percent / 100).clamp(0, 1),
                        minHeight: 6,
                        backgroundColor: hfDivider(context),
                        color: activePalette.accent,
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

  Widget _aiReportCard() {
    final theme = Theme.of(context);
    return HfCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HfSectionHeader(title: 'AI 周报'),
          const SizedBox(height: 10),
          Text(
            _aiReport!,
            style: TextStyle(
              fontSize: AppTheme.textSm,
              height: 1.65,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasOutputData {
    final total = (_outputStats['total_count'] as num?)?.toInt() ?? 0;
    final week = (_outputStats['this_week'] as num?)?.toInt() ?? 0;
    final month = (_outputStats['this_month'] as num?)?.toInt() ?? 0;
    return total > 0 || week > 0 || month > 0;
  }

  Widget _outputCard() {
    final total = (_outputStats['total_count'] as num?)?.toInt() ?? 0;
    final week = (_outputStats['this_week'] as num?)?.toInt() ?? 0;
    final milestones = (_outputStats['milestones'] as num?)?.toInt() ?? 0;
    return HfCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HfSectionHeader(title: '输出记录'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: HfStatCell(value: '$week', label: '本周输出')),
              const SizedBox(width: 10),
              Expanded(child: HfStatCell(value: '$total', label: '累计输出')),
              const SizedBox(width: 10),
              Expanded(child: HfStatCell(value: '$milestones', label: '里程碑')),
            ],
          ),
        ],
      ),
    );
  }
}
