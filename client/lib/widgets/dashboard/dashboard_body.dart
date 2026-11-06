import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/habit.dart';
import '../../models/task.dart';
import '../../models/today_timeline_item.dart';
import '../../services/api/analytics_api.dart';
import '../../services/api/review_api.dart';
import '../../services/data_service.dart';
import '../../theme/app_theme.dart';
import '../../ui/fx.dart';
import '../reflection_composer.dart';
import '../task_swipe_row.dart';
import 'insight_card.dart';

class DashboardBody extends StatefulWidget {
  final List<Task> tasks;
  final List<Habit> habits;
  final ValueChanged<Task>? onTaskTap;
  final ValueChanged<Task>? onTaskToggle;
  final Future<void> Function(Task)? onTaskSwipeComplete;
  final ValueChanged<Habit>? onHabitToggle;
  final ValueChanged<Habit>? onHabitLongPress;
  final VoidCallback? onViewAllTasks;
  final VoidCallback? onViewAllHabits;
  final VoidCallback? onViewReview;
  final Future<List<TodayTimelineItem>> Function()? timelineLoader;
  final VoidCallback? onQuickAdd;
  final VoidCallback? onWriteObservation;
  final VoidCallback? onStartFocus;
  final FutureOr<void> Function()? onRefresh;
  final bool tasksLoading;
  final bool habitsLoading;
  final bool tasksError;
  final bool habitsError;
  final bool listsError;
  final ValueChanged<Insight>? onInsightAction;
  final int refreshTick;
  final Future<Map<String, dynamic>> Function()? dimensionLoader;
  final Future<Map<String, dynamic>> Function()? reviewLoader;

  const DashboardBody({
    super.key,
    required this.tasks,
    required this.habits,
    this.onTaskTap,
    this.onTaskToggle,
    this.onTaskSwipeComplete,
    this.onHabitToggle,
    this.onHabitLongPress,
    this.onViewAllTasks,
    this.onViewAllHabits,
    this.onViewReview,
    this.timelineLoader,
    this.onQuickAdd,
    this.onWriteObservation,
    this.onStartFocus,
    this.onRefresh,
    this.tasksLoading = false,
    this.habitsLoading = false,
    this.tasksError = false,
    this.habitsError = false,
    this.listsError = false,
    this.onInsightAction,
    this.refreshTick = 0,
    this.dimensionLoader,
    this.reviewLoader,
  });

  @override
  State<DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends State<DashboardBody> {
  bool _dimensionLoading = true;
  bool _reviewLoading = true;
  bool _dimensionLoadFailed = false;
  bool _reviewLoadFailed = false;
  bool _timelineLoading = true;
  bool _timelineLoadFailed = false;
  bool _timelineExpanded = false;
  List<TodayTimelineItem> _timeline = const [];
  List<Map<String, dynamic>> _dimensions = const [];
  List<Insight> _insights = const [];
  Map<String, dynamic> _facts = const {};
  final Set<String> _ignored = {};
  int? _revealedTaskId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DashboardBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) _load();
  }

  int _loadVersion = 0;

  Future<void> _load() async {
    final version = ++_loadVersion;
    if (mounted)
      setState(() {
        _dimensionLoading = true;
        _reviewLoading = true;
        _dimensionLoadFailed = false;
        _reviewLoadFailed = false;
        _timelineLoading = true;
        _timelineLoadFailed = false;
      });

    // 独立完成/报错：任意一个辅助接口迟迟未返回，也不能阻塞另一个区域。
    Future<void> loadDimensions() async {
      List<Map<String, dynamic>>? parsed;
      try {
        final data = await (widget.dimensionLoader ??
            AnalyticsApi.getDimensionSummary)();
        parsed = (data['dimensions'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .take(4)
            .toList(growable: false);
      } catch (_) {
        // 失败不是空数据，不覆盖上次成功读取的结果。
      }
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _dimensionLoading = false;
        _dimensionLoadFailed = parsed == null;
        if (parsed != null) _dimensions = parsed;
      });
    }

    Future<void> loadReview() async {
      List<Insight>? insights;
      Map<String, dynamic>? facts;
      try {
        final data = await (widget.reviewLoader ?? ReviewApi.getTodayReview)();
        insights = (data['questions'] as List? ?? const [])
            .whereType<Map>()
            .take(1)
            .map((item) => Insight.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false);
        facts = data['facts'] is Map
            ? Map<String, dynamic>.from(data['facts'] as Map)
            : <String, dynamic>{};
      } catch (_) {
        // 今日提问与四维统计各自退化，不遮挡任务/习惯。
      }
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _reviewLoading = false;
        _reviewLoadFailed = insights == null;
        if (insights != null) {
          _insights = insights;
          _facts = facts ?? <String, dynamic>{};
        }
      });
    }

    Future<void> loadTimeline() async {
      List<TodayTimelineItem>? items;
      try {
        items = await (widget.timelineLoader ?? ReviewApi.getTodayTimeline)();
      } catch (_) {
        // Timeline is independent: the main Today workspace must remain usable.
      }
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _timelineLoading = false;
        _timelineLoadFailed = items == null;
        if (items != null) _timeline = items;
      });
    }

    await Future.wait([loadDimensions(), loadReview(), loadTimeline()]);
  }

  Widget _card(Widget child, {EdgeInsetsGeometry? padding}) {
    return FxCard(
      padding: padding ?? const EdgeInsets.all(SlowlightSpacing.xl),
      color: fxSurface(context),
      borderRadius: SlowlightRadius.lg,
      border: Border.all(color: fxBorder(context)),
      expanded: true,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 首次进入时核心任务与习惯立即可用，辅助数据缓慢/失败不挡主页面。
    final desktop = ResponsiveLayout.isDesktopOrWider(context);
    return FxRefresh(
      onRefresh: () async {
        await _load();
        await widget.onRefresh?.call();
      },
      child: ListView(
        key: const PageStorageKey('today.workspace.scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: SlowlightPageInsets.scroll(
          context,
          bottom: desktop ? 40 : 112,
        ),
        children: [
          _header(desktop),
          if (widget.listsError) ...[
            const SizedBox(height: SlowlightSpacing.md),
            const Text('清单读取失败；已加载的任务、习惯和工具仍可使用。'),
            FxButton(
                label: '重试加载',
                variant: FxButtonVariant.outline,
                onPressed: widget.onRefresh),
          ],
          const SizedBox(height: SlowlightSpacing.xl),
          desktop ? _desktop() : _mobile(),
        ],
      ),
    );
  }

  Widget _header(bool desktop) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    if (!desktop) {
      // The Android prototype has one compact date/focus line. The shell owns
      // the page title; do not insert a second descriptive heading here.
      final date = Text(
        '${now.month}月${now.day}日 · ${weekdays[now.weekday - 1]}',
        key: const ValueKey('today.mobile.date'),
        style: SlowlightTypography.sectionTitle(context)
            .copyWith(fontWeight: FontWeight.w700),
      );
      final focus = widget.onStartFocus == null
          ? null
          : FxButton(
              label: '开始专注',
              icon: LucideIcons.timer,
              variant: FxButtonVariant.outline,
              size: FxButtonSize.sm,
              onPressed: widget.onStartFocus,
            );
      if (focus == null) return date;
      return LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        if (constraints.maxWidth < 300 * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              date,
              const SizedBox(height: SlowlightSpacing.xs),
              Align(alignment: Alignment.centerRight, child: focus),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: date),
            const SizedBox(width: SlowlightSpacing.md),
            focus,
          ],
        );
      });
    }

    final subtitle =
        '${now.month} 月 ${now.day} 日 ${weekdays[now.weekday - 1]} · 记录真实发生的事';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '今天，发生了什么',
                style: SlowlightTypography.pageTitle(context)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: SlowlightTypography.caption(context)
                    .copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (widget.onWriteObservation != null)
          FxButton(
            label: '记录观察',
            icon: LucideIcons.penLine,
            variant: FxButtonVariant.outline,
            size: FxButtonSize.sm,
            onPressed: widget.onWriteObservation,
          ),
        if (widget.onWriteObservation != null && widget.onQuickAdd != null)
          const SizedBox(width: SlowlightSpacing.md),
        if (widget.onQuickAdd != null)
          FxButton(
            label: '添加任务',
            icon: LucideIcons.plus,
            size: FxButtonSize.sm,
            onPressed: widget.onQuickAdd,
          ),
      ],
    );
  }

  // 主工作台：事实优先、行动就近，所有数据使用现有 Review/Analytics 边界。
  Widget _desktop() => Column(
        children: [
          _overviewCard(),
          const SizedBox(height: SlowlightSpacing.xl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    _timelineCard(),
                    if (_shouldShowQuestion) ...[
                      const SizedBox(height: SlowlightSpacing.xl),
                      _questionCard(),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    _taskCard(maxItems: 4, mobile: false),
                    const SizedBox(height: SlowlightSpacing.xl),
                    _habitCard(maxItems: 4, mobile: false),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SlowlightSpacing.xl),
          _dimensionCard(mobile: false),
        ],
      );

  // 移动端严格按已确认原型：今日任务 → 习惯 → 今天的轨迹。
  // 今日事实已有回顾页的“今日概况”提供，桌面工作台仍保留原有统计。
  Widget _mobile() => Column(
        children: [
          _taskCard(maxItems: 3, mobile: true),
          const SizedBox(height: SlowlightSpacing.xl),
          _habitCard(maxItems: 3, mobile: true),
          const SizedBox(height: SlowlightSpacing.xl),
          _timelineCard(mobile: true),
        ],
      );

  Widget _overviewCard() {
    final theme = Theme.of(context);
    final counts = <(String, String)>[
      ('任务完成', _factNumber('task_completed')),
      ('专注分钟', _factNumber('focus_minutes')),
      ('习惯记录', _factNumber('habit_checked')),
    ];
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FxSectionHeader(
            title: '今日事实',
            trailingWidget: widget.onStartFocus == null
                ? null
                : FxButton(
                    label: '开始专注',
                    icon: LucideIcons.timer,
                    variant: FxButtonVariant.ghost,
                    size: FxButtonSize.sm,
                    onPressed: widget.onStartFocus,
                  ),
          ),
          const SizedBox(height: SlowlightSpacing.md),
          Row(
            children: [
              for (var i = 0; i < counts.length; i++) ...[
                if (i > 0)
                  Container(
                    height: 36,
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: SlowlightSpacing.md),
                    color: fxDivider(context),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(counts[i].$2,
                          style: SlowlightTypography.hero(context)
                              .copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(counts[i].$1,
                          style: SlowlightTypography.caption(context).copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (_reviewLoadFailed) ...[
            const SizedBox(height: 8),
            _partialUnavailable('今日事实暂时无法读取'),
          ],
        ],
      ),
      padding: const EdgeInsets.all(SlowlightSpacing.xl),
    );
  }

  String _factNumber(String key) {
    if (_reviewLoadFailed || _reviewLoading) return '—';
    return ((_facts[key] as num?)?.toInt() ?? 0).toString();
  }

  Widget _timelineCard({bool mobile = false}) {
    final previewLimit = mobile ? 3 : 5;
    final items = _timelineExpanded
        ? _timeline
        : _timeline.take(previewLimit).toList(growable: false);
    final status = _timelineLoadFailed
        ? '读取失败'
        : _timelineLoading
            ? '读取中'
            : '${_timeline.length} 条记录';
    final header = FxSectionHeader(
      title: '今天的轨迹',
      titleStyle: mobile
          ? SlowlightTypography.body(context).copyWith(
              fontWeight: FontWeight.w600,
            )
          : null,
      trailing: mobile && widget.onViewReview != null ? null : status,
      trailingWidget: widget.onViewReview == null
          ? null
          : mobile
              ? _mobileSectionActions(
                  status,
                  '进入回顾 →',
                  widget.onViewReview!,
                )
              : FxButton(
                  label: '进入回顾',
                  variant: FxButtonVariant.ghost,
                  size: FxButtonSize.sm,
                  onPressed: widget.onViewReview,
                ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_timelineLoadFailed)
          _partialUnavailable('今天的轨迹暂时无法读取')
        else if (_timelineLoading && _timeline.isEmpty)
          _empty('正在读取今天的轨迹…', compact: mobile)
        else if (_timeline.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SlowlightSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('今天还没有行为记录。',
                    style: SlowlightTypography.secondary(context)),
                if (!mobile && widget.onWriteObservation != null)
                  FxButton(
                    label: '记录此刻的想法',
                    variant: FxButtonVariant.ghost,
                    size: FxButtonSize.sm,
                    onPressed: widget.onWriteObservation,
                  ),
              ],
            ),
          )
        else ...[
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) FxSeparator.horizontal(color: fxDivider(context)),
            _timelineRow(items[i]),
          ],
          if (_timeline.length > previewLimit)
            Align(
              alignment: Alignment.centerLeft,
              child: FxButton(
                label: _timelineExpanded ? '收起记录' : '展开更多记录',
                variant: FxButtonVariant.ghost,
                size: FxButtonSize.sm,
                onPressed: () =>
                    setState(() => _timelineExpanded = !_timelineExpanded),
              ),
            ),
        ],
      ],
    );
    if (mobile) {
      return Column(
        key: const ValueKey('today.section.timeline'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: SlowlightSpacing.md),
          _card(
            content,
            padding: const EdgeInsets.symmetric(
              horizontal: SlowlightSpacing.xl,
              vertical: SlowlightSpacing.xs,
            ),
          ),
        ],
      );
    }
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: SlowlightSpacing.xs),
          content,
        ],
      ),
      padding: const EdgeInsets.all(SlowlightSpacing.xl),
    );
  }

  Widget _timelineRow(TodayTimelineItem item) {
    final theme = Theme.of(context);
    final icon = switch (item.kind) {
      'task_completed' => LucideIcons.checkCheck,
      'habit_checked' => LucideIcons.repeat,
      'session_ended' => LucideIcons.timer,
      'observation' => LucideIcons.penLine,
      _ => LucideIcons.bookOpen,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item.category} · ${item.timeLabel}',
                    style: SlowlightTypography.caption(context)
                        .copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 3),
                Text(item.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: SlowlightTypography.body(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dimensionCard({required bool mobile}) {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FxSectionHeader(
            title: '最近 7 天 · 四维足迹',
            trailingWidget: widget.onViewReview == null
                ? null
                : FxButton(
                    label: '进入回顾',
                    variant: FxButtonVariant.ghost,
                    size: FxButtonSize.sm,
                    onPressed: widget.onViewReview,
                  ),
          ),
          const SizedBox(height: SlowlightSpacing.md),
          if (_dimensionLoadFailed)
            _partialUnavailable('四维统计暂时不可用')
          else if (_dimensionLoading && _dimensions.isEmpty)
            _empty('正在读取四维统计…')
          else if (_dimensions.isEmpty)
            _empty('还没有四维行为记录')
          else if (_dimensions.every(
              (item) => (item['active_days'] as List? ?? const []).isEmpty))
            _empty('最近 7 天还没有归属四维的行为足迹')
          else
            LayoutBuilder(
              builder: (context, constraints) {
                // 四维卡片只根据当前组件真实宽度决定列数；

                // 字体放大通过内容自然增高处理，不在 130% 强制单列。

                final columns = constraints.maxWidth >= 320 ? 2 : 1;
                final gap = 8.0;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: _dimensions
                      .map(
                        (item) => SizedBox(
                          width: width,
                          child: _dimensionItem(item, compact: mobile),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
        ],
      ),
      padding: const EdgeInsets.all(SlowlightSpacing.xl),
    );
  }

  Widget _dimensionItem(Map<String, dynamic> item, {required bool compact}) {
    final theme = Theme.of(context);
    final color = _parseColor(item['color']?.toString());
    final active = _activeDays(item);
    final activeCount =
        _lastSevenDays().where((day) => active.contains(_dateKey(day))).length;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SlowlightSpacing.md,
        vertical: SlowlightSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        border: Border.all(color: color.withValues(alpha: .18)),
        borderRadius: BorderRadius.circular(SlowlightRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item['name']?.toString() ?? '',
              style: SlowlightTypography.caption(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (compact) ...[
            const SizedBox(width: 8),
            Expanded(
              child: FxProgress(
                value: activeCount / 7,
                height: 6,
                color: color,
                backgroundColor: color.withValues(alpha: .12),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$activeCount/7 天',
              style: SlowlightTypography.caption(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ] else
            ..._lastSevenDays().map(
              (day) => Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(left: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active.contains(_dateKey(day))
                      ? color
                      : fxSubtleSurface(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _mobileSectionActions(
    String status,
    String label,
    VoidCallback onPressed,
  ) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          status,
          style: SlowlightTypography.caption(context)
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: SlowlightSpacing.xs),
        FxButton(
          label: label,
          variant: FxButtonVariant.ghost,
          size: FxButtonSize.sm,
          onPressed: onPressed,
        ),
      ],
    );
  }

  Widget _taskCard({required int maxItems, required bool mobile}) {
    final completed = widget.tasks.where((task) => task.isCompleted).length;
    // Android: pending tasks must not be pushed out of the short Today preview
    // by completed tasks returned first from the repository. Preserve the
    // source order within each group and keep desktop ordering unchanged.
    final previewTasks = mobile
        ? widget.tasks.where((task) => !task.isCompleted).followedBy(
              widget.tasks.where((task) => task.isCompleted),
            )
        : widget.tasks;
    final visible = previewTasks.take(maxItems).toList(growable: false);
    final status = widget.tasksLoading
        ? '读取中'
        : widget.tasksError
            ? (visible.isEmpty ? '数量未知' : '上次数据')
            : '${completed}/${widget.tasks.length} 完成';
    final header = FxSectionHeader(
      title: '今日任务',
      titleStyle: mobile
          ? SlowlightTypography.body(context).copyWith(
              fontWeight: FontWeight.w600,
            )
          : null,
      trailing: mobile && widget.onViewAllTasks != null ? null : status,
      trailingWidget: widget.onViewAllTasks == null
          ? null
          : mobile
              ? _mobileSectionActions(
                  status,
                  '查看全部 →',
                  widget.onViewAllTasks!,
                )
              : FxButton(
                  label: '查看全部',
                  variant: FxButtonVariant.ghost,
                  size: FxButtonSize.sm,
                  onPressed: widget.onViewAllTasks,
                ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.tasksLoading || widget.tasksError)
          _coreStatus('任务', widget.tasksLoading, widget.tasksError,
              visible.isNotEmpty),
        if (visible.isEmpty && !widget.tasksLoading && !widget.tasksError)
          mobile
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: SlowlightSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('今天暂时没有任务',
                          style: SlowlightTypography.secondary(context)
                              .copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: SlowlightSpacing.xs),
                      Text('在右下角添加第一件想做的事。',
                          style: SlowlightTypography.caption(context).copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                    ],
                  ),
                )
              : _emptyWithNext(
                  '今天暂时没有任务',
                  '先写下一件想做的事',
                  widget.onQuickAdd,
                )
        else
          ...visible.map((task) => _taskRow(task, mobile)),
      ],
    );
    if (mobile) {
      return Column(
        key: const ValueKey('today.section.tasks'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: SlowlightSpacing.md),
          _card(
            content,
            padding: const EdgeInsets.symmetric(
              horizontal: SlowlightSpacing.xl,
              vertical: SlowlightSpacing.xs,
            ),
          ),
        ],
      );
    }
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, content],
      ),
      padding: const EdgeInsets.fromLTRB(
        SlowlightSpacing.xl,
        SlowlightSpacing.xl,
        SlowlightSpacing.xl,
        SlowlightSpacing.md,
      ),
    );
  }

  Widget _taskRow(Task task, bool mobile) {
    final theme = Theme.of(context);
    final meta = _taskMeta(task);
    final largeText =
        MediaQuery.textScalerOf(context).scale(SlowlightTypography.bodySize) >=
            SlowlightTypography.bodySize * 1.3;
    final row = FxInkWell(
      borderRadius: BorderRadius.circular(SlowlightRadius.md),
      onTap: () => widget.onTaskTap?.call(task),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          color: fxSurface(context),
          border: Border(bottom: BorderSide(color: fxDivider(context))),
        ),
        child: Row(
          children: [
            if (!mobile) ...[
              Container(
                width: 3,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.priorityColor(task.priority),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 7),
            ],
            FxInkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: widget.onTaskToggle == null
                  ? null
                  : () {
                      if (mobile) HapticFeedback.lightImpact();
                      widget.onTaskToggle?.call(task);
                    },
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: task.isCompleted
                          ? AppTheme.success
                          : Colors.transparent,
                      border: Border.all(
                        color: task.isCompleted
                            ? AppTheme.success
                            : theme.colorScheme.outline,
                        width: 1.5,
                      ),
                    ),
                    child: task.isCompleted
                        ? const Icon(
                            Icons.check,
                            size: 11,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: largeText ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: SlowlightTypography.body(context).copyWith(
                      fontWeight: FontWeight.w500,
                      decoration:
                          task.isCompleted ? TextDecoration.lineThrough : null,
                      color: task.isCompleted
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      maxLines: largeText ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: SlowlightTypography.caption(
                        context,
                      ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!mobile ||
        !SlowlightPlatformDensity.usesMobileTouchTargets ||
        task.isCompleted ||
        widget.onTaskToggle == null) {
      return KeyedSubtree(
        key: ValueKey('today-task-${task.id}'),
        child: row,
      );
    }
    return TaskSwipeRow(
      key: ValueKey('today-task-${task.id}'),
      open: _revealedTaskId == task.id,
      onOpenChanged: (open) {
        final next = open ? task.id : null;
        if (_revealedTaskId != next) {
          setState(() => _revealedTaskId = next);
        }
      },
      onPostpone: () => _postponeTask(task),
      onComplete: () async {
        HapticFeedback.lightImpact();
        if (widget.onTaskSwipeComplete != null) {
          await widget.onTaskSwipeComplete!(task);
        } else {
          widget.onTaskToggle?.call(task);
        }
      },
      onMore: () => widget.onTaskTap?.call(task),
      child: row,
    );
  }

  Future<void> _postponeTask(Task task) async {
    try {
      HapticFeedback.lightImpact();
      await DataService().postponeTask(task.id, null);
      if (!mounted) return;
      FxNotice.showContent(context, Text('已顺延到明天'));
      widget.onRefresh?.call();
    } catch (_) {
      if (!mounted) return;
      FxNotice.showContent(context, Text('顺延任务失败'));
    }
  }

  Widget _habitCard({required int maxItems, required bool mobile}) {
    final checked = widget.habits.where((habit) => habit.checkedToday).length;
    final visible = widget.habits.take(maxItems).toList(growable: false);
    final status = widget.habitsLoading
        ? '读取中'
        : widget.habitsError
            ? (visible.isEmpty ? '数量未知' : '上次数据')
            : widget.habits.isEmpty
                ? '暂无习惯'
                : '${checked}/${widget.habits.length} 已打卡';
    final header = FxSectionHeader(
      title: '习惯',
      titleStyle: mobile
          ? SlowlightTypography.body(context).copyWith(
              fontWeight: FontWeight.w600,
            )
          : null,
      trailing: mobile && widget.onViewAllHabits != null ? null : status,
      trailingWidget: widget.onViewAllHabits == null
          ? null
          : mobile
              ? _mobileSectionActions(
                  status,
                  '查看全部 →',
                  widget.onViewAllHabits!,
                )
              : FxButton(
                  label: '查看全部',
                  variant: FxButtonVariant.ghost,
                  size: FxButtonSize.sm,
                  onPressed: widget.onViewAllHabits,
                ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.habitsLoading || widget.habitsError)
          _coreStatus('习惯', widget.habitsLoading, widget.habitsError,
              visible.isNotEmpty),
        if (visible.isEmpty && !widget.habitsLoading && !widget.habitsError)
          _emptyWithNext(
            '还没有习惯记录',
            '去创建第一个习惯',
            widget.onViewAllHabits,
            compact: mobile,
          )
        else
          ...visible.map((habit) => _habitRow(habit, mobile)),
      ],
    );
    if (mobile) {
      return Column(
        key: const ValueKey('today.section.habits'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: SlowlightSpacing.md),
          _card(
            content,
            padding: const EdgeInsets.symmetric(
              horizontal: SlowlightSpacing.xl,
              vertical: SlowlightSpacing.xs,
            ),
          ),
        ],
      );
    }
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, content],
      ),
      padding: const EdgeInsets.fromLTRB(
        SlowlightSpacing.xl,
        SlowlightSpacing.xl,
        SlowlightSpacing.xl,
        SlowlightSpacing.md,
      ),
    );
  }

  Widget _coreStatus(String name, bool loading, bool error, bool hasData) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SlowlightSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (loading)
          const FxCircularProgress()
        else ...[
          Text(hasData ? '${name}刷新失败，以下为上次数据。' : '${name}暂时无法加载，当前数量未知。'),
          FxButton(
              label: '重新加载$name',
              variant: FxButtonVariant.outline,
              onPressed: widget.onRefresh),
        ],
      ]),
    );
  }

  Widget _habitRow(Habit habit, bool mobile) {
    final theme = Theme.of(context);
    final color = _parseColor(habit.color);
    if (mobile) {
      return Container(
        key: ValueKey('today.habit.${habit.id}'),
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: fxDivider(context))),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(SlowlightRadius.md),
              ),
              child: Text(
                habit.icon,
                style: const TextStyle(fontSize: SlowlightTypography.bodySize),
              ),
            ),
            const SizedBox(width: SlowlightSpacing.md),
            Expanded(
              child: FxInkWell(
                onTap: widget.onViewAllHabits,
                onLongPress: widget.onHabitLongPress == null
                    ? null
                    : () => widget.onHabitLongPress?.call(habit),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: SlowlightControlSize.minTouchTarget,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        habit.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SlowlightTypography.secondary(context)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        habit.frequencyText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SlowlightTypography.caption(context).copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (habit.streakCount > 0) ...[
              const SizedBox(width: SlowlightSpacing.xs),
              Text(
                '🔥 ${habit.streakCount}',
                style: SlowlightTypography.caption(context).copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(width: SlowlightSpacing.md),
            // The visible mark stays small; the existing FxIconButton
            // retains the platform 44dp hit area and focus behavior.
            Stack(
              alignment: Alignment.center,
              children: [
                if (habit.checkedToday && !habit.allowMultiplePerDay)
                  IgnorePointer(
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.success.withValues(alpha: .10),
                      ),
                    ),
                  ),
                FxIconButton(
                  key: ValueKey('today.habit.record.${habit.id}'),
                  icon: habit.allowMultiplePerDay
                      ? LucideIcons.circlePlus
                      : habit.checkedToday
                          ? LucideIcons.circleCheck
                          : LucideIcons.circle,
                  iconSize: SlowlightIconSize.xl,
                  foregroundColor: habit.checkedToday && !habit.allowMultiplePerDay
                      ? AppTheme.success
                      : theme.colorScheme.onSurfaceVariant,
                  tooltip: habit.allowMultiplePerDay
                      ? '为「${habit.name}」新增一次记录'
                      : habit.checkedToday
                          ? '已记录「${habit.name}」，点击可取消今天的打卡'
                          : '记录「${habit.name}」今天的打卡',
                  onPressed: widget.onHabitToggle == null
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          widget.onHabitToggle?.call(habit);
                        },
                ),
              ],
            ),
          ],
        ),
      );
    }
    return FxInkWell(
      borderRadius: BorderRadius.circular(SlowlightRadius.md),
      onTap: widget.onHabitToggle == null
          ? null
          : () {
              if (mobile) HapticFeedback.lightImpact();
              widget.onHabitToggle?.call(habit);
            },
      onLongPress: !mobile || widget.onHabitLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onHabitLongPress?.call(habit);
            },
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: fxDivider(context))),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(SlowlightRadius.md),
              ),
              child: Text(habit.icon,
                  style:
                      const TextStyle(fontSize: SlowlightTypography.bodySize)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                habit.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SlowlightTypography.secondary(
                  context,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (habit.streakCount > 0)
              Text(
                '🔥 ${habit.streakCount}',
                style: SlowlightTypography.caption(
                  context,
                ).copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            const SizedBox(width: 8),
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: habit.checkedToday ? color : Colors.transparent,
                border: Border.all(
                  color: habit.checkedToday
                      ? color
                      : theme.colorScheme.outlineVariant,
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.check,
                size: 13,
                color: habit.checkedToday
                    ? Colors.white
                    : theme.colorScheme.outline,
              ),
            ),
            const SizedBox(width: 9),
          ],
        ),
      ),
    );
  }

  Widget _partialUnavailable(String message) => Row(
        children: [
          Expanded(
            child: Text(message, style: SlowlightTypography.secondary(context)),
          ),
          FxButton(
            label: '重试',
            size: FxButtonSize.sm,
            variant: FxButtonVariant.ghost,
            onPressed: _load,
          ),
        ],
      );

  bool get _shouldShowQuestion =>
      _reviewLoading ||
      _reviewLoadFailed ||
      _insights.any((item) => !_ignored.contains(item.id));

  Widget _questionCard() {
    final theme = Theme.of(context);
    final visible = _insights
        .where((item) => !_ignored.contains(item.id))
        .take(1)
        .toList(growable: false);
    final insight = _reviewLoadFailed || visible.isEmpty ? null : visible.first;
    return _card(
      FxInkWell(
        borderRadius: BorderRadius.circular(SlowlightRadius.lg),
        onTap: insight == null ? null : () => _respond(insight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FxChip(
              label: '今日提问',
              backgroundColor: activePalette.accent.withValues(alpha: .12),
              foregroundColor: activePalette.accent,
              borderRadius: SlowlightRadius.pill,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            ),
            const SizedBox(height: 8),
            if (_reviewLoadFailed)
              _partialUnavailable('今日提问暂时无法读取')
            else
              Text(
                insight?.content ??
                    (_reviewLoading ? '正在读取今日提问…' : '今天暂时没有特别需要关注的变化。'),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: SlowlightTypography.secondary(context).copyWith(
                  fontWeight:
                      insight == null ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
            if (insight != null) ...[
              const SizedBox(height: 8),
              Text(
                '点击去回应 →',
                style: SlowlightTypography.caption(
                  context,
                ).copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
      padding: const EdgeInsets.all(SlowlightSpacing.xl),
    );
  }

  Future<void> _respond(Insight insight) async {
    if (widget.onInsightAction != null) {
      widget.onInsightAction?.call(insight);
      return;
    }
    final saved = await ReflectionComposer.show(
      context,
      questionId: insight.id.isEmpty ? null : insight.id,
      prompt: insight.content,
      contextData: {'question_type': insight.type, 'source': 'today'},
    );
    if (saved && mounted && insight.id.isNotEmpty) {
      setState(() => _ignored.add(insight.id));
    }
  }

  // 空状态保留单一全局主入口；这里仅提供就近的轻量下一步链接。
  Widget _emptyWithNext(
    String title,
    String action,
    VoidCallback? onNext, {
    bool compact = false,
  }) =>
      Padding(
        padding: EdgeInsets.symmetric(
          vertical: compact ? SlowlightSpacing.xs : SlowlightSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: SlowlightTypography.secondary(context).copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
            if (onNext != null)
              FxButton(
                label: action,
                variant: FxButtonVariant.link,
                size: FxButtonSize.sm,
                onPressed: onNext,
              ),
          ],
        ),
      );

  Widget _empty(String text, {bool compact = false}) => Padding(
        padding: EdgeInsets.symmetric(
          vertical: compact ? SlowlightSpacing.xs : SlowlightSpacing.md,
        ),
        child: Text(
          text,
          style: SlowlightTypography.secondary(
            context,
          ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );

  Set<String> _activeDays(Map<String, dynamic> item) =>
      (item['active_days'] as List?)
          ?.map((value) => value.toString())
          .toSet() ??
      <String>{};

  List<DateTime> _lastSevenDays() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(
      7,
      (index) => today.subtract(Duration(days: 6 - index)),
    );
  }

  String _taskMeta(Task task) {
    final parts = <String>[];
    final listName = task.list?.name.trim() ?? '';
    if (listName.isNotEmpty) parts.add(listName);
    if (task.isCompleted && task.completedAt != null) {
      parts.add(
        '${_two(task.completedAt!.hour)}:${_two(task.completedAt!.minute)} 完成',
      );
    } else if (task.dueTime != null && task.dueTime!.trim().isNotEmpty) {
      parts.add('${task.dueTime!.trim()} 前');
    } else if (task.dueDate != null) {
      parts.add('${task.dueDate!.month}/${task.dueDate!.day}');
    } else if (!task.isCompleted) {
      parts.add('随时');
    }
    return parts.join(' · ');
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${_two(value.month)}-${_two(value.day)}';
  String _two(int value) => value.toString().padLeft(2, '0');
  Color _parseColor(String? value) {
    try {
      var hex = (value ?? '').replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return AppTheme.info;
    }
  }
}

