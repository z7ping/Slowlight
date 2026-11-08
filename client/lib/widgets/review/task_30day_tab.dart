import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/reflection_entry.dart';
import '../../models/today_timeline_item.dart';
import '../../repositories/reflection_repository.dart';
import '../../services/api/analytics_api.dart';
import '../../services/api/review_api.dart';
import '../../theme/app_theme.dart';
import '../../ui/fx.dart';
import '../../utils/local_time_boundary.dart';
import 'completed_task_item.dart';
import 'review_timeline_item.dart';

class TaskMonthTab extends StatefulWidget {
  final ReflectionRepository? reflectionRepository;
  final TextEditingController? responseDraftController;
  final VoidCallback? onOpenWeekly;
  /// Test seams only. Production reuses the existing Review/Analytics APIs.
  final Future<Map<String, dynamic>> Function()? tasksReviewLoader;
  final Future<List<Map<String, dynamic>>> Function()? dailyTrendLoader;
  final Future<ReviewPeriodTimeline> Function()? periodTimelineLoader;
  final Future<ReviewPeriodTimeline> Function({required int offset})?
      periodTimelinePageLoader;

  const TaskMonthTab({
    super.key,
    this.reflectionRepository,
    this.responseDraftController,
    this.onOpenWeekly,
    this.tasksReviewLoader,
    this.dailyTrendLoader,
    this.periodTimelineLoader,
    this.periodTimelinePageLoader,
  });

  @override
  State<TaskMonthTab> createState() => _TaskMonthTabState();
}

class _TaskMonthTabState extends State<TaskMonthTab> {
  bool _loading = true;
  bool _reviewRefreshing = false;
  bool _hasConfirmedReview = false;
  String? _error;
  String? _refreshError;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _trendDays = const [];
  bool _trendLoadFailed = false;
  bool _trendRefreshing = false;
  ReviewPeriodTimeline? _periodTimeline;
  bool _periodTimelineFailed = false;
  bool _periodTimelineLoading = false;
  bool _showAllPeriodEvents = false;
  ReviewPeriodTimeline? _periodPage;
  int _periodPageOffset = 0;
  bool _loadingPeriodPage = false;
  int? _failedPeriodPageOffset;
  int _loadVersion = 0;
  int _visibleTasks = 20;
  late final ReflectionRepository _responseRepo =
      widget.reflectionRepository ?? ReflectionRepository();
  late final TextEditingController _responseDraft =
      widget.responseDraftController ?? TextEditingController();
  ReflectionEntry? _savedResponse;
  String? _responsePeriodKey;
  bool _responseChecked = false;
  bool _responseLoading = false;
  bool _responseSaving = false;
  bool _responseUnknown = false;

  @override
  void dispose() {
    if (widget.responseDraftController == null) _responseDraft.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_responseSaving) return;
    if (_responseUnknown) {
      FxNotice.showContent(
        context,
        const Text('上次回应保存结果尚未确认，请先核对回应再刷新'),
        variant: FxNoticeVariant.warning,
      );
      return;
    }
    final version = ++_loadVersion;
    setState(() {
      _reviewRefreshing = true;
      if (_responseLoading) _responseChecked = false;
      _responseLoading = false;
      _loadingPeriodPage = false;
      _periodTimelineLoading = false;
      _loading = !_hasConfirmedReview;
      _error = null;
      _refreshError = null;
    });

    // First confirm the requested 30-day facts. Starting a new trend read
    // before that can blend fresh trend facts into an older primary snapshot.
    try {
      final result = await (widget.tasksReviewLoader ??
          () => ReviewApi.getTasksReview(days: 30))();
      if (!mounted || version != _loadVersion) return;
      // The key follows the confirmed local rolling window, including today.
      final now = DateTime.now();
      final start = LocalTimeBoundary.dateKey(
        LocalTimeBoundary.addCalendarDays(LocalTimeBoundary.dayStart(now), -29),
      );
      final end = LocalTimeBoundary.dateKey(now);
      final periodKey = 'review-30d:$start:$end';
      setState(() {
        if (_responsePeriodKey != periodKey) {
          _savedResponse = null;
          _responseChecked = false;
          _responseUnknown = false;
        }
        _responsePeriodKey = periodKey;
        _data = result;
        _hasConfirmedReview = true;
        _reviewRefreshing = false;
        _loading = false;
        _visibleTasks = 20;
        _trendRefreshing = _trendDays.isNotEmpty;
        _trendLoadFailed = false;
        _periodTimeline = null;
        _periodTimelineFailed = false;
        _periodTimelineLoading = false;
        _showAllPeriodEvents = false;
        _periodPage = null;
        _periodPageOffset = 0;
        _loadingPeriodPage = false;
        _failedPeriodPageOffset = null;
      });
      if (!SlowlightPlatformDensity.usesMobileTouchTargets) {
        unawaited(_loadPeriodResponse(version, periodKey));
      }
      // Optional trend must not delay the confirmed primary task facts.
      unawaited(_loadTrend(version));
      unawaited(_loadPeriodTimeline(version));
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _reviewRefreshing = false;
        if (_hasConfirmedReview) {
          _refreshError = error.toString();
        } else {
          _error = error.toString();
        }
        _loading = false;
      });
    }
  }

  Future<void> _loadPeriodResponse(int version, String periodKey) async {
    if (_responseSaving) return;
    setState(() {
      _responseLoading = true;
      _responseChecked = false;
    });
    try {
      final found = await _responseRepo.findPeriodResponse(periodKey);
      if (!mounted || version != _loadVersion ||
          periodKey != _responsePeriodKey) return;
      setState(() {
        _savedResponse = found;
        _responseChecked = true;
        _responseUnknown = false;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      // A failed authoritative read is not evidence of no saved reply.
      setState(() => _responseChecked = false);
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _responseLoading = false);
      }
    }
  }

  Future<void> _savePeriodResponse() async {
    final key = _responsePeriodKey;
    final content = _responseDraft.text.trim();
    if (!_responseChecked || _responseSaving || _responseUnknown ||
        _reviewRefreshing || _savedResponse != null || _refreshError != null ||
        key == null || content.isEmpty) return;
    final version = _loadVersion;
    setState(() => _responseSaving = true);
    try {
      final parts = key.split(':');
      final saved = await _responseRepo.create(
        content: content,
        questionId: key,
        context: {
          'source': 'review',
          'question_type': 'period',
          'period': 'rolling30',
          'period_start': parts[1],
          'period_end': parts[2],
        },
      );
      if (!mounted || version != _loadVersion || key != _responsePeriodKey) {
        return;
      }
      setState(() {
        _savedResponse = saved;
        _responseUnknown = false;
        _responseDraft.clear();
      });
      FxNotice.showContent(context, Text(saved.id < 0
          ? '回应已保存在本机，等待云端同步' : '回应已保存'));
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() => _responseUnknown = true);
      FxNotice.showContent(
        context,
        const Text('保存结果未确认，草稿已保留，请先核对记录'),
        variant: FxNoticeVariant.warning,
      );
    } finally {
      if (mounted) setState(() => _responseSaving = false);
    }
  }

  Widget _periodResponseCard() => FxCard(
    expanded: true,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FxSectionHeader(title: '近 30 天回应'),
        const SizedBox(height: 10),
        if (_responseLoading)
          const FxCircularProgress()
        else if (_savedResponse != null)
          Text(_savedResponse!.content, style: SlowlightTypography.body(context))
        else ...[
          Text('这段时间有什么事，让你想多了解自己一点？',
              style: SlowlightTypography.secondary(context)),
          const SizedBox(height: 10),
          FxInput(
            controller: _responseDraft,
            placeholder: '写下这段时间的感受与理解…',
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
                            _reviewRefreshing || _responsePeriodKey == null
                        ? null : () => _loadPeriodResponse(
                            _loadVersion, _responsePeriodKey!),
                  )
                : FxButton(
                    label: _responseSaving ? '保存中…' : '保存回应',
                    size: FxButtonSize.sm,
                    onPressed: _responseSaving || _refreshError != null ||
                            _reviewRefreshing
                        ? null : _savePeriodResponse,
                  ),
          ),
        ],
      ],
    ),
  );

  Future<void> _loadTrend(int version) async {
    try {
      final trend = await (widget.dailyTrendLoader ??
          () => AnalyticsApi.getDailyTrend(days: 30))();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _trendDays = trend;
        _trendRefreshing = false;
        _trendLoadFailed = false;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      // Do not erase a previously confirmed trend on a failed refresh.
      setState(() {
        _trendRefreshing = false;
        _trendLoadFailed = true;
      });
    }
  }

  Future<void> _loadPeriodTimeline(int version) async {
    try {
      final facts = await (widget.periodTimelineLoader ??
          () => ReviewApi.getPeriodTimeline(period: 'month'))();
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
          ? ReviewApi.getPeriodTimeline(period: 'month', offset: offset)
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
            Text('近 30 天轨迹读取未确认，已有任务统计不受影响。',
                style: SlowlightTypography.secondary(context))
          else if (facts == null)
            Text('近 30 天轨迹读取中…',
                style: SlowlightTypography.secondary(context))
          else if (visible.isEmpty)
            Text('近 30 天还没有可追溯的行为记录。',
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

    // Habit check-ins alone do not establish a task-completion history.
    final hasTaskData =
        ((summary['completed_count'] as num?)?.toInt() ?? 0) > 0 ||
        ((summary['created_count'] as num?)?.toInt() ?? 0) > 0 ||
        tasks.isNotEmpty ||
        // Old trend may still be shown with a stale marker, but it cannot
        // establish activity in the newly-confirmed 30-day task snapshot.
        (!_trendRefreshing && !_trendLoadFailed && _trendDays.any(
          (day) => ((day['task_completed'] as num?)?.toInt() ?? 0) > 0,
        ));

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
                  _periodEvidenceCard(),
                  if (!SlowlightPlatformDensity.usesMobileTouchTargets) ...[
                    const SizedBox(height: 14),
                    _periodResponseCard(),
                  ],
                  const SizedBox(height: 14),
                  if (_trendRefreshing && _trendDays.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '趋势核对中，当前趋势与习惯汇总仍来自上次读取。',
                        style: SlowlightTypography.secondary(context),
                      ),
                    ),
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
                          if (_trendDays.isNotEmpty)
                            Text(
                              '习惯汇总与下方趋势来自上次核对，非本次刷新结果。',
                              style: SlowlightTypography.caption(context),
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
                    ),
                  if (_trendDays.isNotEmpty && hasTaskData) ...[
                    const SizedBox(height: SlowlightSpacing.md),
                    _trendCard(),
                  ] else if (!_trendLoadFailed && hasTaskData)
                    _trendCard()
                  else if (!_trendLoadFailed)
                    const FxEmptyState(
                      icon: LucideIcons.calendarDays,
                      title: '近 30 天还没有任务记录',
                      subtitle: '有记录后，这里会展示完成趋势与任务分布。',
                      padding: EdgeInsets.symmetric(vertical: 24),
                    ),
                  if (hasTaskData && dist.isNotEmpty) ...[
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
            FxStatCell(
              value: summary['completed_count'] is num ? '$completed' : '—',
              label: '完成任务',
            ),
            FxStatCell(
              value: summary['created_count'] is num ? '$created' : '—',
              label: '新建任务',
            ),
            FxStatCell(
              value: _trendDays.isEmpty ? '—' : '$habitCount',
              label: _trendDays.isNotEmpty &&
                      (_trendRefreshing || _trendLoadFailed)
                  ? '习惯记录（上次核对）'
                  : '习惯记录',
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
