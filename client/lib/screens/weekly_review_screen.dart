import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../ai/ai_service.dart';
import '../models/today_timeline_item.dart';
import '../models/reflection_entry.dart';
import '../repositories/reflection_repository.dart';
import '../services/api/analytics_api.dart';
import '../services/api/review_api.dart';
import '../widgets/review/review_timeline_item.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';

/// 每周回顾：作为「更多工具」内容页嵌入主壳。
class WeeklyReviewScreen extends StatefulWidget {
  final bool embedded;
  final ReflectionRepository? reflectionRepository;
  /// Optional test seams; production always uses the existing AnalyticsApi.
  final Future<Map<String, dynamic>> Function()? reviewLoader;
  final Future<Map<String, dynamic>> Function()? outputStatsLoader;
  final Future<List<Map<String, dynamic>>> Function()? dailyTrendLoader;
  final Future<ReviewPeriodTimeline> Function()? periodTimelineLoader;
  final Future<ReviewPeriodTimeline> Function({required int offset})?
      periodTimelinePageLoader;

  const WeeklyReviewScreen({
    super.key,
    this.embedded = false,
    this.reflectionRepository,
    this.reviewLoader,
    this.outputStatsLoader,
    this.dailyTrendLoader,
    this.periodTimelineLoader,
    this.periodTimelinePageLoader,
  });

  @override
  State<WeeklyReviewScreen> createState() => _WeeklyReviewScreenState();
}

class _WeeklyReviewScreenState extends State<WeeklyReviewScreen> {
  bool _loading = true;
  bool _hasConfirmedReview = false;
  bool _generatingAi = false;
  String? _loadError;
  String? _refreshError;
  bool _outputStatsFailed = false;
  bool _dailyTrendFailed = false;
  String? _aiReport;
  Map<String, dynamic> _review = {};
  Map<String, dynamic> _outputStats = {};
  List<Map<String, dynamic>> _dailyTrend = const [];
  ReviewPeriodTimeline? _periodTimeline;
  bool _periodTimelineFailed = false;
  bool _showAllPeriodEvents = false;
  ReviewPeriodTimeline? _periodPage;
  int _periodPageOffset = 0;
  bool _loadingPeriodPage = false;
  int? _failedPeriodPageOffset;
  int _loadVersion = 0;
  late final ReflectionRepository _responseRepo =
      widget.reflectionRepository ?? ReflectionRepository();
  final TextEditingController _responseDraft = TextEditingController();
  bool _responseChecked = false;
  bool _responseLoading = false;
  bool _responseSaving = false;
  bool _responseUnknown = false;
  ReflectionEntry? _savedResponse;

  @override
  void dispose() {
    _responseDraft.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadReview();
  }

  Future<void> _loadReview() async {
    final version = ++_loadVersion;
    if (mounted) {
      setState(() {
        _loading = !_hasConfirmedReview;
        _loadError = null;
        _refreshError = null;
      });
    }

    // Confirm the primary week before fetching optional statistics.
    // Otherwise a failed primary refresh mixes new auxiliary data into an
    // older confirmed week and silently changes what the user is reviewing.
    try {
      final review = await (widget.reviewLoader ??
          AnalyticsApi.getWeeklyReview)();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _review = review;
        _hasConfirmedReview = true;
        _loading = false;
        // The new review starts a fresh evidence cohort. Old trend/output
        // belongs to the previous snapshot and must not be mixed into it.
        _outputStats = {};
        _dailyTrend = const [];
        _outputStatsFailed = false;
        _dailyTrendFailed = false;
        _periodTimeline = null;
        _periodTimelineFailed = false;
        _showAllPeriodEvents = false;
        _periodPage = null;
        _periodPageOffset = 0;
        _loadingPeriodPage = false;
        _failedPeriodPageOffset = null;
        _aiReport = null;
      });
      // The optional queries must never delay the confirmed weekly summary.
      unawaited(_loadOutputStats(version));
      unawaited(_loadDailyTrend(version));
      unawaited(_loadPeriodTimeline(version));
      unawaited(_loadWeekResponse(version));
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _loading = false;
        if (_hasConfirmedReview) {
          _refreshError = error.toString();
        } else {
          _loadError = error.toString();
        }
      });
    }
  }

  Future<void> _loadWeekResponse(int version) async {
    final start = _review['week_start']?.toString() ?? '';
    final end = _review['week_end']?.toString() ?? '';
    if (start.isEmpty || end.isEmpty) return;
    setState(() {
      _responseLoading = true;
      _responseChecked = false;
    });
    try {
      final entries = await _responseRepo.recent(limit: 100);
      if (!mounted || version != _loadVersion) return;
      ReflectionEntry? found;
      for (final entry in entries) {
        if (entry.entryType == 'reflection' &&
            entry.context['source'] == 'weekly_review' &&
            entry.context['week_start'] == start &&
            entry.context['week_end'] == end) {
          found = entry;
          break;
        }
      }
      setState(() {
        _savedResponse = found;
        _responseChecked = true;
        _responseUnknown = false;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() => _responseChecked = false);
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _responseLoading = false);
      }
    }
  }

  Future<void> _saveWeekResponse() async {
    final start = _review['week_start']?.toString() ?? '';
    final end = _review['week_end']?.toString() ?? '';
    final content = _responseDraft.text.trim();
    if (!_responseChecked || _responseSaving || _responseUnknown ||
        _savedResponse != null || _refreshError != null ||
        start.isEmpty || end.isEmpty || content.isEmpty) return;
    final version = _loadVersion;
    setState(() => _responseSaving = true);
    try {
      final saved = await _responseRepo.create(
        content: content,
        context: {
          'source': 'weekly_review',
          'week_start': start,
          'week_end': end,
        },
      );
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _savedResponse = saved;
        _responseUnknown = false;
        _responseDraft.clear();
      });
      _message(saved.id < 0 ? '回应已保存在本机，等待云端同步' : '回应已保存');
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() => _responseUnknown = true);
      _message('保存结果未确认，草稿已保留，请先核对记录');
    } finally {
      if (mounted) setState(() => _responseSaving = false);
    }
  }

  Widget _weekResponseCard() {
    return FxCard(
      expanded: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FxSectionHeader(title: '本周回应'),
          const SizedBox(height: 10),
          if (_responseLoading)
            const FxCircularProgress()
          else if (_savedResponse != null)
            Text(_savedResponse!.content, style: SlowlightTypography.body(context))
          else ...[
            FxInput(
              controller: _responseDraft,
              placeholder: '写下这一周的感受与理解…',
              maxLines: 4,
            ),
            const SizedBox(height: 8),
            if (!_responseChecked || _responseUnknown)
              Text(
                _responseUnknown
                    ? '保存结果尚未确认。核对已有回应后才能再次保存。'
                    : '回应记录暂时无法核对，不能安全保存。',
                style: SlowlightTypography.caption(context),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: _responseUnknown || !_responseChecked
                  ? FxButton(
                      label: '核对回应',
                      variant: FxButtonVariant.secondary,
                      size: FxButtonSize.sm,
                      onPressed: _responseLoading || _responseSaving
                          ? null : () => _loadWeekResponse(_loadVersion),
                    )
                  : FxButton(
                      label: _responseSaving ? '保存中…' : '保存回应',
                      size: FxButtonSize.sm,
                      onPressed: _responseSaving || _refreshError != null
                          ? null : _saveWeekResponse,
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadOutputStats(int version) async {
    try {
      final stats = await (widget.outputStatsLoader ??
          () => AnalyticsApi.getOutputStats(period: 'week'))();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _outputStats = stats;
        _outputStatsFailed = false;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      // Last confirmed output stats remain available for display.
      setState(() => _outputStatsFailed = true);
    }
  }

  Future<void> _loadDailyTrend(int version) async {
    try {
      final trend = await (widget.dailyTrendLoader ??
          () => AnalyticsApi.getDailyTrend(days: 7))();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _dailyTrend = trend;
        _dailyTrendFailed = false;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() => _dailyTrendFailed = true);
    }
  }

  Future<void> _loadPeriodTimeline(int version) async {
    try {
      final facts = await (widget.periodTimelineLoader ??
          () => ReviewApi.getPeriodTimeline(period: 'week'))();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _periodTimeline = facts;
        _periodTimelineFailed = false;
        _periodPage = facts;
        _periodPageOffset = 0;
        _showAllPeriodEvents = false;
        _failedPeriodPageOffset = null;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() => _periodTimelineFailed = true);
    }
  }

  Future<void> _loadPeriodPage(int offset) async {
    if (_loadingPeriodPage || _periodTimeline == null || offset < 0) return;
    if (offset == 0) {
      setState(() {
        _periodPage = _periodTimeline;
        _periodPageOffset = 0;
        _failedPeriodPageOffset = null;
      });
      return;
    }
    final version = _loadVersion;
    setState(() {
      _loadingPeriodPage = true;
      _failedPeriodPageOffset = null;
    });
    try {
      final page = await (widget.periodTimelinePageLoader == null
          ? ReviewApi.getPeriodTimeline(period: 'week', offset: offset)
          : widget.periodTimelinePageLoader!(offset: offset));
      if (!mounted || version != _loadVersion) return;
      if (page.observationCount != _periodTimeline!.observationCount ||
          page.items.isEmpty) {
        setState(() {
          _failedPeriodPageOffset = offset;
          _loadingPeriodPage = false;
        });
        return;
      }
      setState(() {
        _periodPage = page;
        _periodPageOffset = offset;
        _loadingPeriodPage = false;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _failedPeriodPageOffset = offset;
        _loadingPeriodPage = false;
      });
    }
  }

  Widget _periodEvidenceCard() {
    final facts = _periodTimeline;
    final page = _showAllPeriodEvents ? (_periodPage ?? facts) : facts;
    final visible = page?.items.take(_showAllPeriodEvents ? 40 : 20)
            .toList(growable: false) ??
        const <TodayTimelineItem>[];
    return FxCard(
      expanded: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FxSectionHeader(
            title: '发生过的事',
            trailing: facts == null
                ? '待读取'
                : '观察记录 ${facts.observationCount} 条',
          ),
          const SizedBox(height: 10),
          if (_periodTimelineFailed)
            Text(
              '本周轨迹读取未确认，已有统计不受影响。',
              style: SlowlightTypography.secondary(context),
            )
          else if (facts == null)
            Text('本周轨迹读取中…',
                style: SlowlightTypography.secondary(context))
          else if (visible.isEmpty)
            Text('本周还没有可追溯的行为记录。',
                style: SlowlightTypography.secondary(context))
          else ...[
            if (!_showAllPeriodEvents &&
                (facts.items.length > visible.length || facts.hasMore))
              Text('先显示最近 ${visible.length} 条事件',
                  style: SlowlightTypography.caption(context)),
            if (_showAllPeriodEvents)
              Text('第 ${_periodPageOffset ~/ 40 + 1} 页 · ${visible.length} 条事件',
                  style: SlowlightTypography.caption(context)),
            ...List.generate(visible.length, (index) {
              final entry = visible[index];
              return ReviewTimelineItem(
                color: switch (entry.kind) {
                  'task_completed' => AppTheme.chartGreen,
                  'habit_checked' => AppTheme.chartYellow,
                  'observation' => AppTheme.chartPurple,
                  _ => AppTheme.info,
                },
                time: '${entry.occurredAt.month}/${entry.occurredAt.day} ${entry.timeLabel}',
                title: entry.kind == 'observation'
                    ? '记录观察' : entry.description,
                note: entry.kind == 'observation' ? entry.title : null,
                last: index == visible.length - 1,
              );
            }),
            if (!_showAllPeriodEvents &&
                (facts.items.length > 20 || facts.hasMore)) ...[
              const SizedBox(height: 8),
              FxButton(
                label: '查看全部事件',
                variant: FxButtonVariant.outline,
                size: FxButtonSize.sm,
                onPressed: () => setState(() => _showAllPeriodEvents = true),
              ),
            ],
            if (_showAllPeriodEvents) ...[
              if (_loadingPeriodPage)
                Text('正在读取本页记录…',
                    style: SlowlightTypography.secondary(context)),
              if (_failedPeriodPageOffset != null)
                Text('本页读取未完成，仍显示上一页；可重新读取。',
                    style: SlowlightTypography.secondary(context)),
              if (_periodPageOffset > 0 ||
                  page?.hasMore == true ||
                  _failedPeriodPageOffset != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                  if (_periodPageOffset > 0)
                    FxButton(
                      label: '上一页',
                      variant: FxButtonVariant.outline,
                      size: FxButtonSize.sm,
                      onPressed: _loadingPeriodPage ? null
                          : () => _loadPeriodPage(_periodPageOffset - 40),
                    ),
                  if (page?.hasMore == true &&
                      _failedPeriodPageOffset == null)
                    FxButton(
                      label: '下一页',
                      variant: FxButtonVariant.outline,
                      size: FxButtonSize.sm,
                      onPressed: _loadingPeriodPage ? null
                          : () => _loadPeriodPage(_periodPageOffset +
                              (page?.items.length ?? 0)),
                    ),
                  if (_failedPeriodPageOffset != null)
                    FxButton(
                      label: '重试读取',
                      variant: FxButtonVariant.secondary,
                      size: FxButtonSize.sm,
                      onPressed: _loadingPeriodPage ? null
                          : () => _loadPeriodPage(_failedPeriodPageOffset!),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _confirmGenerateAiReport() async {
    if (_generatingAi || !_hasConfirmedReview) return;
    if (_refreshError != null) {
      _message('本周统计刷新尚未确认，请核对后再生成 AI 周报');
      return;
    }
    final version = _loadVersion;
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '确认生成 AI 周报？',
      content: '将本周已确认的记录发送给当前启用的 AI 服务生成周报。是否继续？',
      confirmText: '确认生成',
    );
    if (confirmed != true || !mounted || version != _loadVersion ||
        _refreshError != null) return;
    await _generateAiReport();
  }

  Future<void> _generateAiReport() async {
    if (_generatingAi || _refreshError != null || !_hasConfirmedReview) return;
    final version = _loadVersion;
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
          if (!_outputStatsFailed) 'output_stats': _outputStats,
          if (!_dailyTrendFailed) 'daily_trend': _dailyTrend,
        },
      });
      if (!mounted || version != _loadVersion) return;
      setState(() => _aiReport = text.trim());
    } catch (e) {
      _message('AI 周报生成失败：$e');
    } finally {
      if (mounted) setState(() => _generatingAi = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    FxNotice.showContent(context, Text(text));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: FxCircularProgress());
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.triangleAlert, size: 24),
            const SizedBox(height: 8),
            Text('每周回顾加载失败', style: SlowlightTypography.cardTitle(context)),
            const SizedBox(height: 4),
            Text(
              '请检查网络或数据服务后重试',
              style: SlowlightTypography.secondary(
                context,
              ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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

    return FxRefresh(
      onRefresh: _loadReview,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: SlowlightPageInsets.scroll(
          context,
          top: widget.embedded ? SlowlightSpacing.xs : null,
          bottom: 72,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_refreshError != null) ...[
                    FxCard(
                      expanded: true,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '本周数据刷新未确认，以下仍为上次成功读取的统计。',
                              style: SlowlightTypography.caption(context),
                            ),
                          ),
                          FxButton(
                            label: '重新加载',
                            variant: FxButtonVariant.outline,
                            size: FxButtonSize.sm,
                            onPressed: _loadReview,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: SlowlightSpacing.md),
                  ],
                  if (!widget.embedded) Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '每周回顾',
                              style: SlowlightTypography.pageTitle(context),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              weekStart.isEmpty
                                  ? '回看这一周真实发生的变化'
                                  : '$weekStart — $weekEnd · 回看真实发生的变化',
                              style: SlowlightTypography.secondary(
                                context,
                              ).copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FxIconButton(
                        tooltip: '刷新',
                        onPressed: _loadReview,
                        icon: LucideIcons.refreshCw,
                      ),
                    ],
                  ),
                  if (!widget.embedded) const SizedBox(height: 14),
                  _summary(),
                  const SizedBox(height: SlowlightSpacing.md),
                  _periodEvidenceCard(),
                   const SizedBox(height: SlowlightSpacing.md),
                   _weekResponseCard(),
                  if (_outputStatsFailed || _dailyTrendFailed) ...[
                    const SizedBox(height: 12),
                    FxCard(
                      padding: const EdgeInsets.all(12),
                      expanded: true,
                      child: Row(
                        children: [
                          const Icon(LucideIcons.triangleAlert, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '部分统计暂时无法读取，未加载的数据不计作零记录。',
                              style: SlowlightTypography.secondary(context),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FxButton(
                            label: '重试',
                            size: FxButtonSize.sm,
                            variant: FxButtonVariant.secondary,
                            onPressed: _loadReview,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (!_hasBehaviorData)
                    const FxEmptyState(
                      icon: LucideIcons.chartNoAxesCombined,
                      title: '这一周还没有行为记录',
                      subtitle: '开始记录后，这里会呈现每一天的变化。',
                      padding: EdgeInsets.symmetric(vertical: 24),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 700;
                        final comparison = _comparison();
                        if (!_hasTimeDistribution) return comparison;
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

  bool get _hasTimeDistribution =>
      (_review['time_distribution'] as List? ?? const []).isNotEmpty;

  bool get _hasBehaviorData {
    const keys = [
      'habit_checked', 'task_completed', 'focus_minutes',
      'habit_last_week', 'task_last_week', 'focus_last_week',
    ];
    return keys.any((key) => ((_review[key] as num?)?.toInt() ?? 0) != 0) ||
        _dailyTrend.any((row) =>
            ((row['task_completed'] as num?)?.toInt() ?? 0) != 0 ||
            ((row['habit_checked'] as num?)?.toInt() ?? 0) != 0);
  }

  Widget _summary() {
    final habitChecked = (_review['habit_checked'] as num?)?.toInt() ?? 0;
    final taskCompleted = (_review['task_completed'] as num?)?.toInt() ?? 0;
    final focusMinutes = (_review['focus_minutes'] as num?)?.toInt() ?? 0;
    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '本周记录'),
          const SizedBox(height: 12),
          _statLayout([
            FxStatCell(value: '$habitChecked', label: '习惯打卡', suffix: ' 次'),
            FxStatCell(value: '$taskCompleted', label: '完成任务', suffix: ' 个'),
            FxStatCell(value: '$focusMinutes', label: '专注', suffix: ' 分钟'),
          ]),
          if (_hasBehaviorData && _dailyTrend.isNotEmpty) ...[
            const SizedBox(height: 14),
            _weeklyBars(),
          ],
        ],
      ),
    );
  }

  Widget _statLayout(List<Widget> cells) {
    return FxResponsiveFormGrid(
      minColumnWidth: 160,
      maxColumns: 3,
      horizontalGap: 10,
      verticalGap: 8,
      children: cells,
    );
  }

  Widget _weeklyBars() {
    final theme = Theme.of(context);
    final values = _dailyTrend
        .map((item) {
          final tasks = (item['task_completed'] as num?)?.toInt() ?? 0;
          final habits = (item['habit_checked'] as num?)?.toInt() ?? 0;
          return tasks + habits;
        })
        .toList(growable: false);
    final max = values.fold<int>(1, (a, b) => b > a ? b : a);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '每日记录',
          style: SlowlightTypography.caption(
            context,
          ).copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 92,
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
                              color: activePalette.accent.withValues(
                                alpha: .82,
                              ),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(SlowlightRadius.sm),
                              ),
                            ),
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
        ),
      ],
    );
  }

  Widget _comparison() {
    final theme = Theme.of(context);
    final habitDelta =
        ((_review['habit_checked'] as num?)?.toInt() ?? 0) -
        ((_review['habit_last_week'] as num?)?.toInt() ?? 0);
    final taskDelta =
        ((_review['task_completed'] as num?)?.toInt() ?? 0) -
        ((_review['task_last_week'] as num?)?.toInt() ?? 0);
    final focusDelta =
        ((_review['focus_minutes'] as num?)?.toInt() ?? 0) -
        ((_review['focus_last_week'] as num?)?.toInt() ?? 0);
    final hasData =
        (_review['habit_last_week'] ?? 0) != 0 ||
        (_review['task_last_week'] ?? 0) != 0 ||
        (_review['focus_last_week'] ?? 0) != 0;

    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '和上周比'),
          const SizedBox(height: 10),
          if (!hasData)
            Text(
              '数据积累中，下周会有可对比记录。',
              style: SlowlightTypography.secondary(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else ...[
            _deltaRow('习惯打卡', habitDelta, '次'),
            _deltaRow('完成任务', taskDelta, '个'),
            _deltaRow('专注时长', focusDelta, '分钟'),
          ],
          const SizedBox(height: 10),
          FxInkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: _generatingAi || _refreshError != null
                ? null : _confirmGenerateAiReport,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: activePalette.accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _generatingAi ? '正在生成 AI 周报…' : '生成 AI 周报 →',
                    style: SlowlightTypography.caption(context).copyWith(
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
    final color =
        zero
            ? theme.colorScheme.onSurfaceVariant
            : positive
            ? AppTheme.success
            : AppTheme.warning;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: SlowlightTypography.secondary(context)),
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
          Flexible(
            child: Text(
              '${delta > 0 ? '+' : ''}$delta $unit',
              textAlign: TextAlign.end,
              style: SlowlightTypography.caption(
                context,
              ).copyWith(fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _distribution() {
    final theme = Theme.of(context);
    final tags =
        (_review['time_distribution'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
    tags.sort(
      (a, b) => ((b['total_min'] as num?)?.toInt() ?? 0).compareTo(
        (a['total_min'] as num?)?.toInt() ?? 0,
      ),
    );

    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '时间分布'),
          const SizedBox(height: 10),
          if (tags.isEmpty)
            Text(
              '本周还没有足够的专注分布数据。',
              style: SlowlightTypography.secondary(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                            style: SlowlightTypography.secondary(context),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '$minutes 分钟 · ${percent.toStringAsFixed(0)}%',
                            textAlign: TextAlign.end,
                            style: SlowlightTypography.caption(
                              context,
                            ).copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    FxProgress(
                      value: (percent / 100).clamp(0, 1),
                      height: 6,
                      backgroundColor: theme.colorScheme.outlineVariant,
                      color: activePalette.accent,
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
    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: 'AI 周报'),
          const SizedBox(height: 10),
          Text(
            _aiReport!,
            style: SlowlightTypography.body(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
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
    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '输出记录'),
          const SizedBox(height: 12),
          _statLayout([
            FxStatCell(value: '$week', label: '本周输出'),
            FxStatCell(value: '$total', label: '累计输出'),
            FxStatCell(value: '$milestones', label: '里程碑'),
          ]),
        ],
      ),
    );
  }
}
