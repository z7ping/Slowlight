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
  final TextEditingController? responseDraftController;
  final VoidCallback? onOpenStats;
  final VoidCallback? onOpenTimeDistribution;
  final VoidCallback? onOpenThirtyDays;
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
    this.responseDraftController,
    this.onOpenStats,
    this.onOpenTimeDistribution,
    this.onOpenThirtyDays,
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
  bool _reviewRefreshing = false;
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
  bool _periodTimelineLoading = false;
  bool _showAllPeriodEvents = false;
  String _eventFilter = 'all';
  ReviewPeriodTimeline? _periodPage;
  int _periodPageOffset = 0;
  bool _loadingPeriodPage = false;
  int? _failedPeriodPageOffset;
  int _loadVersion = 0;
  late final ReflectionRepository _responseRepo =
      widget.reflectionRepository ?? ReflectionRepository();
  late final TextEditingController _responseDraft =
      widget.responseDraftController ?? TextEditingController();
  bool _responseChecked = false;
  bool _responseLoading = false;
  bool _responseSaving = false;
  bool _responseUnknown = false;
  ReflectionEntry? _savedResponse;

  @override
  void dispose() {
    if (widget.responseDraftController == null) _responseDraft.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadReview();
  }

  Future<void> _loadReview() async {
    if (_responseSaving) return;
    if (_responseUnknown) {
      _message('上次回应保存结果尚未确认，请先核对回应再刷新');
      return;
    }
    final version = ++_loadVersion;
    if (mounted) {
      setState(() {
        _reviewRefreshing = true;
        // A new revision invalidates any pending response/page request.
        if (_responseLoading) _responseChecked = false;
        _responseLoading = false;
        _loadingPeriodPage = false;
        _periodTimelineLoading = false;
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
      final oldWeek = '${_review['week_start']}:${_review['week_end']}';
      final newWeek = '${review['week_start']}:${review['week_end']}';
      setState(() {
        _review = review;
        _reviewRefreshing = false;
        _hasConfirmedReview = true;
        _loading = false;
        if (oldWeek != newWeek) {
          // Period-scoped responses cannot belong to the newly loaded week.
          // Preserve the unsaved draft until the user explicitly edits it.
          _savedResponse = null;
          _responseChecked = false;
          _responseUnknown = false;
        }
        // The new review starts a fresh evidence cohort. Old trend/output
        // belongs to the previous snapshot and must not be mixed into it.
        _outputStats = {};
        _dailyTrend = const [];
        _outputStatsFailed = false;
        _dailyTrendFailed = false;
        _periodTimeline = null;
        _periodTimelineFailed = false;
        _periodTimelineLoading = false;
        _showAllPeriodEvents = false;
        _eventFilter = 'all';
        _periodPage = null;
        _periodPageOffset = 0;
        _loadingPeriodPage = false;
        _failedPeriodPageOffset = null;
        _aiReport = null;
        _generatingAi = false;
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
        _reviewRefreshing = false;
        if (_hasConfirmedReview) {
          _refreshError = error.toString();
        } else {
          _loadError = error.toString();
        }
      });
    }
  }

  Future<void> _loadWeekResponse(int version) async {
    if (_responseSaving) return;
    final start = _review['week_start']?.toString() ?? '';
    final end = _review['week_end']?.toString() ?? '';
    if (start.isEmpty || end.isEmpty) return;
    setState(() {
      _responseLoading = true;
      _responseChecked = false;
    });
    try {
      final found = await _responseRepo.findPeriodResponse(
        'review-week:$start:$end',
        legacyWeekStart: start,
        legacyWeekEnd: end,
      );
      if (!mounted || version != _loadVersion) return;
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
        _reviewRefreshing || _savedResponse != null || _refreshError != null ||
        start.isEmpty || end.isEmpty || content.isEmpty) return;
    final version = _loadVersion;
    setState(() => _responseSaving = true);
    try {
      final saved = await _responseRepo.create(
        content: content,
        questionId: 'review-week:$start:$end',
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
                      onPressed: _responseLoading || _responseSaving ||
                              _reviewRefreshing
                          ? null : () => _loadWeekResponse(_loadVersion),
                    )
                  : FxButton(
                      label: _responseSaving ? '保存中…' : '保存回应',
                      size: FxButtonSize.sm,
                      onPressed: _responseSaving || _refreshError != null ||
                              _reviewRefreshing
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
      final start = _review['week_start']?.toString() ?? '';
      final end = _review['week_end']?.toString() ?? '';
      // The source covers a rolling seven days; show only confirmed week days.
      final thisWeek = start.isEmpty || end.isEmpty
          ? trend
          : trend.where((row) {
              final day = row['date']?.toString() ?? '';
              return day.compareTo(start) >= 0 && day.compareTo(end) <= 0;
            }).toList(growable: false);
      setState(() {
        _dailyTrend = thisWeek;
        _dailyTrendFailed = false;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() => _dailyTrendFailed = true);
    }
  }

  Future<void> _loadPeriodTimeline(int version) async {
    if (_periodTimelineLoading || _reviewRefreshing) return;
    setState(() {
      _periodTimelineLoading = true;
      _periodTimelineFailed = false;
    });
    try {
      final facts = await (widget.periodTimelineLoader ??
          () => ReviewApi.getPeriodTimeline(period: 'week'))();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _periodTimeline = facts;
        _periodTimelineFailed = false;
        _periodTimelineLoading = false;
        _periodPage = facts;
        _periodPageOffset = 0;
        _showAllPeriodEvents = false;
        _failedPeriodPageOffset = null;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _periodTimelineFailed = true;
        _periodTimelineLoading = false;
      });
    }
  }

  Future<void> _loadPeriodPage(int offset) async {
    if (_reviewRefreshing || _loadingPeriodPage ||
        _periodTimeline == null || offset < 0) return;
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
    final mobile = SlowlightPlatformDensity.usesMobileTouchTargets;
    final page = _showAllPeriodEvents ? (_periodPage ?? facts) : facts;
    final filtered = page?.items.where(
      (item) => !mobile || _eventFilter == 'all' || item.kind == _eventFilter,
    ).toList(growable: false) ?? const <TodayTimelineItem>[];
    final visible = filtered.take(_showAllPeriodEvents ? 40 : mobile ? 8 : 20)
        .toList(growable: false);
    return FxCard(
      expanded: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FxSectionHeader(
            title: mobile ? '近期记录' : '发生过的事',
            trailing: facts == null
                ? '待读取'
                : '观察记录 ${facts.observationCount} 条',
          ),
          const SizedBox(height: 10),
          if (mobile && _eventFilter != 'all') ...[
            FxButton(
              label: '清除筛选',
              variant: FxButtonVariant.ghost,
              size: FxButtonSize.sm,
              onPressed: () => setState(() => _eventFilter = 'all'),
            ),
            const SizedBox(height: SlowlightSpacing.xs),
          ],
          if (_periodTimelineFailed) ...[
            Text(
              '本周轨迹读取未确认，已有统计不受影响。',
              style: SlowlightTypography.secondary(context),
            ),
            const SizedBox(height: 8),
            FxButton(
              label: '重试轨迹',
              variant: FxButtonVariant.secondary,
              size: FxButtonSize.sm,
              onPressed: _reviewRefreshing
                  ? null : () => _loadPeriodTimeline(_loadVersion),
            ),
          ]
          else if (facts == null)
            Text('本周轨迹读取中…',
                style: SlowlightTypography.secondary(context))
          else if (visible.isEmpty)
            Text(
              mobile && _eventFilter != 'all'
                  ? '当前类型暂无已载入记录；其他页面可能还有记录。'
                  : facts.observationCount > 0
                  ? '本周有 ${facts.observationCount} 条观察，事件明细尚未载入。'
                  : '本周还没有可追溯的行为记录。',
              style: SlowlightTypography.secondary(context),
            )
          else ...[
            if (!_showAllPeriodEvents &&
                (facts.items.length > visible.length || facts.hasMore))
              Text('先显示最近 ${visible.length} 条已载入事件',
                  style: SlowlightTypography.caption(context)),
            if (_showAllPeriodEvents)
              Text('第 ${_periodPageOffset ~/ 40 + 1} 页 · ${visible.length} 条事件',
                  style: SlowlightTypography.caption(context)),
            ...List.generate(visible.length, (index) {
              final entry = visible[index];
              return ReviewTimelineItem(
                key: ValueKey('review.week.${entry.id}'),
                kind: entry.kind,
                compact: mobile,
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
                (facts.items.length > (mobile ? 8 : 20) || facts.hasMore)) ...[
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
    if (_generatingAi || !_hasConfirmedReview || _reviewRefreshing) return;
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
        _refreshError != null || _reviewRefreshing) return;
    await _generateAiReport();
  }

  Future<void> _generateAiReport() async {
    if (_generatingAi || _reviewRefreshing ||
        _refreshError != null || !_hasConfirmedReview) return;
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
      if (mounted && version == _loadVersion) {
        _message('AI 周报生成失败：$e');
      }
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _generatingAi = false);
      }
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
                  if (SlowlightPlatformDensity.usesMobileTouchTargets &&
                      (widget.onOpenStats != null ||
                       widget.onOpenTimeDistribution != null ||
                       widget.onOpenThirtyDays != null)) ...[
                    const SizedBox(height: SlowlightSpacing.md),
                    Wrap(
                      spacing: SlowlightSpacing.md,
                      runSpacing: SlowlightSpacing.xs,
                      children: [
                        if (widget.onOpenStats != null)
                          FxButton(
                            label: '查看记录统计',
                            variant: FxButtonVariant.link,
                            size: FxButtonSize.sm,
                            onPressed: widget.onOpenStats,
                          ),
                        if (widget.onOpenTimeDistribution != null)
                          FxButton(
                            label: '查看时间分配',
                            variant: FxButtonVariant.link,
                            size: FxButtonSize.sm,
                            onPressed: widget.onOpenTimeDistribution,
                          ),
                        if (widget.onOpenThirtyDays != null)
                          FxButton(
                            label: '查看近 30 天',
                            variant: FxButtonVariant.link,
                            size: FxButtonSize.sm,
                            onPressed: widget.onOpenThirtyDays,
                          ),
                      ],
                    ),
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
    return (_periodTimeline?.observationCount ?? 0) > 0 ||
        (_periodTimeline?.items.isNotEmpty ?? false) ||
        keys.any((key) => ((_review[key] as num?)?.toInt() ?? 0) != 0) ||
        _dailyTrend.any((row) =>
            ((row['task_completed'] as num?)?.toInt() ?? 0) != 0 ||
            ((row['habit_checked'] as num?)?.toInt() ?? 0) != 0);
  }


  Widget _periodMetric(String value, String label, String kind,
      {bool available = true}) {
    final cell = FxStatCell(value: value, label: label);
    final selected = _eventFilter == kind;
    return Semantics(
      button: available,
      selected: selected,
      label: '$label $value，${available ? selected ? '清除筛选' : '筛选已载入轨迹' : '数据尚未读取'}',
      child: FxInkWell(
        key: ValueKey('review.week.metric.$kind'),
        onTap: !available ? null : () => setState(() {
          _eventFilter = selected ? 'all' : kind;
          _showAllPeriodEvents = false;
        }),
        borderRadius: BorderRadius.circular(SlowlightRadius.md),
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: .08)
                : null,
            borderRadius: BorderRadius.circular(SlowlightRadius.md),
          ),
          child: cell,
        ),
      ),
    );
  }

  Widget _summary() {
    final habitChecked = (_review['habit_checked'] as num?)?.toInt();
    final taskCompleted = (_review['task_completed'] as num?)?.toInt();
    final focusMinutes = (_review['focus_minutes'] as num?)?.toInt();
    final mobile = SlowlightPlatformDensity.usesMobileTouchTargets;
    final observationCount = _periodTimeline?.observationCount;
    return FxCard(
      padding: EdgeInsets.all(mobile ? SlowlightSpacing.xl : 16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FxSectionHeader(title: mobile ? '本期概况' : '本周记录'),
          const SizedBox(height: 12),
          if (mobile)
            FxResponsiveFormGrid(
              minColumnWidth: 96,
              maxColumns: 3,
              horizontalGap: SlowlightSpacing.md,
              verticalGap: SlowlightSpacing.md,
              children: [
                _periodMetric(taskCompleted?.toString() ?? '—',
                    '完成任务', 'task_completed', available: taskCompleted != null),
                _periodMetric(habitChecked?.toString() ?? '—',
                    '习惯记录', 'habit_checked', available: habitChecked != null),
                _periodMetric(
                    observationCount?.toString() ?? '—',
                    '观察记录', 'observation', available: observationCount != null),
              ],
            )
          else
            _statLayout([
              FxStatCell(value: '${habitChecked ?? 0}', label: '习惯打卡', suffix: ' 次'),
              FxStatCell(value: '${taskCompleted ?? 0}', label: '完成任务', suffix: ' 个'),
              FxStatCell(value: '${focusMinutes ?? 0}', label: '专注', suffix: ' 分钟'),
            ]),
          if (_hasBehaviorData && _dailyTrend.isNotEmpty) ...[
            const SizedBox(height: 14),
            if (mobile)
              Text('记录节奏 · 已载入任务与习惯',
                  style: SlowlightTypography.caption(context))
            else
              const SizedBox.shrink(),
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
    // A confirmed zero baseline is still valid; missing keys are not.
    final hasData = const [
      'habit_last_week', 'task_last_week', 'focus_last_week',
    ].every((key) => _review[key] is num);

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
            onTap: _generatingAi || _reviewRefreshing ||
                    _refreshError != null
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
