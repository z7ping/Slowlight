import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/habit.dart';
import '../../models/task.dart';
import '../../services/api/analytics_api.dart';
import '../../services/api/review_api.dart';
import '../../services/data_service.dart';
import '../../theme/app_theme.dart';
import '../../ui/fx.dart';
import '../reflection_composer.dart';
import 'insight_card.dart';

class DashboardBody extends StatefulWidget {
  final List<Task> tasks;
  final List<Habit> habits;
  final ValueChanged<Task>? onTaskTap;
  final ValueChanged<Task>? onTaskToggle;
  final ValueChanged<Habit>? onHabitToggle;
  final ValueChanged<Habit>? onHabitLongPress;
  final VoidCallback? onViewAllTasks;
  final VoidCallback? onViewAllHabits;
  final VoidCallback? onQuickAdd;
  final VoidCallback? onWriteObservation;
  final VoidCallback? onStartFocus;
  final VoidCallback? onRefresh;
  final ValueChanged<Insight>? onInsightAction;
  final int refreshTick;

  const DashboardBody({
    super.key,
    required this.tasks,
    required this.habits,
    this.onTaskTap,
    this.onTaskToggle,
    this.onHabitToggle,
    this.onHabitLongPress,
    this.onViewAllTasks,
    this.onViewAllHabits,
    this.onQuickAdd,
    this.onWriteObservation,
    this.onStartFocus,
    this.onRefresh,
    this.onInsightAction,
    this.refreshTick = 0,
  });

  @override
  State<DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends State<DashboardBody> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _dimensions = const [];
  List<Insight> _insights = const [];
  Map<String, dynamic> _facts = const {};
  final Set<String> _ignored = {};

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

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final values = await Future.wait<dynamic>([
        AnalyticsApi.getDimensionSummary(),
        ReviewApi.getTodayReview(),
      ]);
      if (!mounted) return;
      final dimensionData = values[0] as Map<String, dynamic>;
      final reviewData = values[1] as Map<String, dynamic>;
      setState(() {
        _dimensions = (dimensionData['dimensions'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .take(4)
            .toList(growable: false);
        _insights = (reviewData['questions'] as List? ?? const [])
            .whereType<Map>()
            .take(1)
            .map((item) => Insight.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false);
        _facts =
            reviewData['facts'] is Map
                ? Map<String, dynamic>.from(reviewData['facts'] as Map)
                : <String, dynamic>{};
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

  Widget _card(Widget child, {EdgeInsetsGeometry? padding}) {
    final theme = Theme.of(context);
    return FxCard(
      padding: padding ?? const EdgeInsets.all(16),
      color: fxSurface(context),
      borderRadius: AppTheme.radiusLg,
      border: Border.all(color: fxBorder(context)),
      boxShadow:
          theme.brightness == Brightness.light ? AppTheme.cardShadow : null,
      expanded: true,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _skeleton();
    if (_error != null) return _errorView();
    final desktop = ResponsiveLayout.isDesktopOrWider(context);
    return FxRefresh(
      onRefresh: () async {
        await _load();
        widget.onRefresh?.call();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          desktop ? 24 : 16,
          desktop ? 20 : 14,
          desktop ? 24 : 16,
          40,
        ),
        children: [
          _header(desktop),
          SizedBox(height: desktop ? 18 : 12),
          desktop ? _desktop() : _mobile(),
        ],
      ),
    );
  }

  Widget _header(bool desktop) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    const short = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final subtitle =
        desktop
            ? '${now.month} 月 ${now.day} 日 ${weekdays[now.weekday - 1]} · 你有 ${widget.tasks.length} 个任务和 ${widget.habits.length} 个习惯在今天'
            : '${now.month} 月 ${now.day} 日 ${short[now.weekday - 1]}';
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_greeting(now.hour)} 👋',
          style: SlowlightTypography.pageTitle(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: SlowlightTypography.caption(
            context,
          ).copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
    if (!desktop) return copy;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: copy),
        if (widget.onWriteObservation != null)
          FxButton(
            label: '写下观察',
            icon: LucideIcons.penLine,
            variant: FxButtonVariant.outline,
            size: FxButtonSize.sm,
            onPressed: widget.onWriteObservation,
          ),
        if (widget.onWriteObservation != null && widget.onQuickAdd != null)
          const SizedBox(width: 8),
        if (widget.onQuickAdd != null)
          FxButton(
            label: '记录任务',
            icon: LucideIcons.plus,
            size: FxButtonSize.sm,
            onPressed: widget.onQuickAdd,
          ),
      ],
    );
  }

  Widget _desktop() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 280,
        child: Column(
          children: [
            _dimensionCard(),
            const SizedBox(height: 14),
            _focusCard(),
            const SizedBox(height: 14),
            _questionCard(),
          ],
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          children: [
            _taskCard(maxItems: 3, mobile: false),
            const SizedBox(height: 14),
            _habitCard(maxItems: 3, mobile: false),
          ],
        ),
      ),
    ],
  );

  Widget _mobile() => Column(
    children: [
      _dimensionCard(),
      const SizedBox(height: 12),
      _taskCard(maxItems: 2, mobile: true),
      const SizedBox(height: 12),
      _habitCard(maxItems: 2, mobile: true),
      const SizedBox(height: 12),
      _questionCard(),
      const SizedBox(height: 12),
      _focusCard(),
    ],
  );

  Widget _dimensionCard() {
    final mobile = !ResponsiveLayout.isDesktopOrWider(context);
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '四维足迹', trailing: '近 7 天'),
          const SizedBox(height: 10),
          if (_dimensions.isEmpty)
            _empty('还没有四维行为记录')
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
      padding: EdgeInsets.all(mobile ? 12 : 16),
    );
  }

  Widget _dimensionItem(Map<String, dynamic> item, {required bool compact}) {
    final theme = Theme.of(context);
    final color = _parseColor(item['color']?.toString());
    final active = _activeDays(item);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        border: Border.all(color: color.withValues(alpha: .18)),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
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
          if (compact)
            Text(
              '${active.length}/7 天',
              style: SlowlightTypography.caption(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            ..._lastSevenDays().map(
              (day) => Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(left: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      active.contains(_dateKey(day))
                          ? color
                          : fxSubtleSurface(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _taskCard({required int maxItems, required bool mobile}) {
    final completed = widget.tasks.where((task) => task.isCompleted).length;
    final visible = widget.tasks.take(maxItems).toList(growable: false);
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FxSectionHeader(
            title: '今日任务',
            trailing: '$completed/${widget.tasks.length} 完成',
            trailingWidget:
                widget.onViewAllTasks == null
                    ? null
                    : FxButton(
                      label: '查看全部',
                      variant: FxButtonVariant.ghost,
                      size: FxButtonSize.sm,
                      onPressed: widget.onViewAllTasks,
                    ),
          ),
          if (visible.isEmpty)
            _empty('今天暂时没有任务')
          else
            ...visible.map((task) => _taskRow(task, mobile)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        mobile ? 12 : 16,
        mobile ? 12 : 16,
        mobile ? 12 : 16,
        7,
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
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      onTap: () => widget.onTaskTap?.call(task),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
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
              onTap:
                  widget.onTaskToggle == null
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
                      color:
                          task.isCompleted
                              ? AppTheme.success
                              : Colors.transparent,
                      border: Border.all(
                        color:
                            task.isCompleted
                                ? AppTheme.success
                                : theme.colorScheme.outline,
                        width: 1.5,
                      ),
                    ),
                    child:
                        task.isCompleted
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
                      color:
                          task.isCompleted
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
    if (!mobile || task.isCompleted) return row;
    return _MobileTaskSwipeRow(
      key: ValueKey('today-task-${task.id}'),
      onPostpone: () => _postponeTask(task),
      onComplete: () {
        HapticFeedback.lightImpact();
        widget.onTaskToggle?.call(task);
      },
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
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FxSectionHeader(
            title: '习惯',
            trailing: '$checked/${widget.habits.length} 已打卡',
            trailingWidget:
                widget.onViewAllHabits == null
                    ? null
                    : FxButton(
                      label: '查看全部',
                      variant: FxButtonVariant.ghost,
                      size: FxButtonSize.sm,
                      onPressed: widget.onViewAllHabits,
                    ),
          ),
          if (visible.isEmpty)
            _empty('还没有习惯记录')
          else
            ...visible.map((habit) => _habitRow(habit, mobile)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        mobile ? 12 : 16,
        mobile ? 12 : 16,
        mobile ? 12 : 16,
        7,
      ),
    );
  }

  Widget _habitRow(Habit habit, bool mobile) {
    final theme = Theme.of(context);
    final color = _parseColor(habit.color);
    return FxInkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      onTap:
          widget.onHabitToggle == null
              ? null
              : () {
                if (mobile) HapticFeedback.lightImpact();
                widget.onHabitToggle?.call(habit);
              },
      onLongPress:
          !mobile || widget.onHabitLongPress == null
              ? null
              : () {
                HapticFeedback.mediumImpact();
                widget.onHabitLongPress?.call(habit);
              },
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
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
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Text(habit.icon, style: const TextStyle(fontSize: SlowlightTypography.bodySize)),
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
                  color:
                      habit.checkedToday
                          ? color
                          : theme.colorScheme.outlineVariant,
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.check,
                size: 13,
                color:
                    habit.checkedToday
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

  Widget _focusCard() {
    final theme = Theme.of(context);
    final count = (_facts['focus_count'] as num?)?.toInt() ?? 0;
    final minutes = (_facts['focus_minutes'] as num?)?.toInt() ?? 0;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '专注', trailing: '今日'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$count',
                style: SlowlightTypography.hero(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '次 · $minutes 分钟',
                style: SlowlightTypography.secondary(
                  context,
                ).copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          if (widget.onStartFocus != null) ...[
            const SizedBox(height: 10),
            FxButton(
              label: '开始专注',
              icon: LucideIcons.timer,
              variant: FxButtonVariant.outline,
              size: FxButtonSize.sm,
              expanded: true,
              onPressed: widget.onStartFocus,
            ),
          ],
        ],
      ),
    );
  }

  Widget _questionCard() {
    final theme = Theme.of(context);
    final visible = _insights
        .where((item) => !_ignored.contains(item.id))
        .take(1)
        .toList(growable: false);
    final insight = visible.isEmpty ? null : visible.first;
    return FxInkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      onTap: insight == null ? null : () => _respond(insight),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: fxDivider(context),
          radius: AppTheme.radiusLg,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: fxSurface(context),
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FxChip(
                label: '今日提问',
                backgroundColor: activePalette.accent.withValues(alpha: .12),
                foregroundColor: activePalette.accent,
                borderRadius: 999,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              ),
              const SizedBox(height: 8),
              Text(
                insight?.content ?? '今天暂时没有特别需要关注的变化。',
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
      ),
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

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
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
  String _greeting(int hour) =>
      hour < 12
          ? '早上好'
          : hour < 18
          ? '下午好'
          : '晚上好';

  Color _parseColor(String? value) {
    try {
      var hex = (value ?? '').replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return AppTheme.info;
    }
  }

  Widget _skeleton() => ListView(
    padding: const EdgeInsets.all(20),
    children: List.generate(
      4,
      (index) => Container(
        height: index == 0 ? 64 : 150,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.warmGray300.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        ),
      ),
    ),
  );

  Widget _errorView() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('今天的数据加载失败'),
        const SizedBox(height: 10),
        FxButton(
          label: '重试',
          variant: FxButtonVariant.secondary,
          onPressed: _load,
        ),
      ],
    ),
  );
}

class _MobileTaskSwipeRow extends StatefulWidget {
  final Widget child;
  final VoidCallback onPostpone;
  final VoidCallback onComplete;

  const _MobileTaskSwipeRow({
    super.key,
    required this.child,
    required this.onPostpone,
    required this.onComplete,
  });

  @override
  State<_MobileTaskSwipeRow> createState() => _MobileTaskSwipeRowState();
}

class _MobileTaskSwipeRowState extends State<_MobileTaskSwipeRow> {
  static const double _actionWidth = 70;
  static const double _maxReveal = _actionWidth * 2;
  double _offset = 0;

  void _drag(DragUpdateDetails details) {
    setState(() {
      _offset = (_offset + details.delta.dx).clamp(-_maxReveal, 0).toDouble();
    });
  }

  void _end(DragEndDetails details) {
    final open =
        details.velocity.pixelsPerSecond.dx < -250 || _offset < -_maxReveal / 2;
    setState(() => _offset = open ? -_maxReveal : 0);
  }

  void _run(VoidCallback action) {
    setState(() => _offset = 0);
    action();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _SwipeAction(
                  width: _actionWidth,
                  background: AppTheme.warning,
                  label: '⏱ 顺延',
                  onTap: () => _run(widget.onPostpone),
                ),
                _SwipeAction(
                  width: _actionWidth,
                  background: AppTheme.success,
                  label: '✓ 完成',
                  onTap: () => _run(widget.onComplete),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: Offset(_offset, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: _drag,
              onHorizontalDragEnd: _end,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeAction extends StatelessWidget {
  final double width;
  final Color background;
  final String label;
  final VoidCallback onTap;

  const _SwipeAction({
    required this.width,
    required this.background,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      child: FxInkWell(
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: SlowlightTypography.captionSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    final path =
        Path()..addRRect(
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
        );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + 5, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
