import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../controllers/habit_controller.dart';
import '../models/habit.dart';
import '../models/habit_log.dart';
import '../repositories/habit_repository.dart';
import '../repositories/tag_links_repository.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/habit_checkin_dialog.dart';
import '../widgets/habit_editor_dialog.dart';

class HabitToolScreen extends StatefulWidget {
  final HabitRepository? repository;
  final TagLinksRepository? tagLinksRepository;
  final Future<HabitEditorValue?> Function(BuildContext, {Habit? habit})? editor;

  const HabitToolScreen({
    super.key, this.repository, this.tagLinksRepository, this.editor,
  });

  @override
  State<HabitToolScreen> createState() => _HabitToolScreenState();
}

class _HabitToolScreenState extends State<HabitToolScreen> {
  late final HabitController _controller;
  late final TagLinksRepository _tagLinks;
  bool _editingHabit = false;
  int? _expandedHabitId;
  int _filter = 0; // 全部 / 待记录 / 已记录
  final Set<int> _pendingHabitActions = <int>{};

  @override
  void initState() {
    super.initState();
    _tagLinks = widget.tagLinksRepository ?? TagLinksRepository();
    _controller = HabitController(repository: widget.repository)
      ..addListener(_onChanged);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _message(String text) {
    if (!mounted) return;
    FxNotice.showContent(context, Text(text));
  }

  /// 习惯本体成功后标签关联可能单独失败（尤其云端模式），不能说
  /// “创建失败”再让用户重建，否则已有习惯会被重复创建。
  Future<bool> _saveHabitTags(int habitId, List<int> ids, String action) async {
    try {
      await _tagLinks.replaceFor(TagLinkedEntity.habit, habitId, ids);
      return true;
    } catch (e) {
      if (mounted) {
        FxNotice.showContent(
          context,
          Text('习惯已$action，但标签保存失败。原习惯仍保留：$e'),
          variant: FxNoticeVariant.warning,
          action: FxNoticeAction(
            label: '重试保存标签',
            onPressed: () async {
              final ok = await _saveHabitTags(habitId, ids, action);
              if (ok) _message('标签已补充保存');
            },
          ),
        );
      }
      return false;
    }
  }

  Future<void> _createHabit() async {
    if (_editingHabit) return;
    _editingHabit = true;
    try {
      final value = widget.editor == null
          ? await HabitEditorDialog.show(context)
          : await widget.editor!(context);
      if (value == null || !mounted) return;
      Habit created;
      try {
        created = await _controller.create(
          name: value.name,
          icon: value.icon,
          color: value.color,
          frequency: value.frequency,
          recordType: value.recordType,
          recordUnit: value.recordUnit,
          recordTimeLabel: value.recordTimeLabel,
          allowMultiplePerDay: value.allowMultiplePerDay,
          goalPeriod: value.goalPeriod,
          goalMetric: value.goalMetric,
          goalValue: value.goalValue,
          targetDays: value.targetDays,
          systemTagId: value.systemTagId,
          preferredPeriod: value.preferredPeriod,
          durationMin: value.durationMin,
          generateTask: value.generateTask,
          showCheckinDialog: value.showCheckinDialog,
          specificTime: value.specificTime,
          reminderAt: value.reminderAt,
        );
      } catch (e) {
        _message('创建结果未确认，请先在习惯列表核对，避免重复创建：$e');
        return;
      }
      if (value.tagIds != null && value.tagIds!.isNotEmpty &&
          !await _saveHabitTags(created.id, List<int>.from(value.tagIds!), '创建')) {
        return;
      }
      _message('习惯已创建');
    } finally {
      _editingHabit = false;
    }
  }

  Future<void> _editHabit(Habit habit) async {
    if (_editingHabit) return;
    _editingHabit = true;
    try {
      final value = widget.editor == null
          ? await HabitEditorDialog.show(context, habit: habit)
          : await widget.editor!(context, habit: habit);
      if (value == null || !mounted) return;
      try {
        await _controller.update(
          habit,
          name: value.name,
          icon: value.icon,
          color: value.color,
          frequency: value.frequency,
          recordType: value.recordType,
          recordUnit: value.recordUnit,
          recordTimeLabel: value.recordTimeLabel,
          allowMultiplePerDay: value.allowMultiplePerDay,
          goalPeriod: value.goalPeriod,
          goalMetric: value.goalMetric,
          goalValue: value.goalValue,
          targetDays: value.targetDays,
          systemTagId: value.systemTagId,
          updateSystemTag: true,
          preferredPeriod: value.preferredPeriod,
          durationMin: value.durationMin,
          generateTask: value.generateTask,
          showCheckinDialog: value.showCheckinDialog,
          specificTime: value.specificTime,
          reminderAt: value.reminderAt,
        );
      } catch (e) {
        _message('更新结果未确认，请先查看习惯详情再重试：$e');
        return;
      }
      if (value.tagIds != null &&
          !await _saveHabitTags(habit.id, List<int>.from(value.tagIds!), '更新')) {
        return;
      }
      _message('习惯已更新');
    } finally {
      _editingHabit = false;
    }
  }

  // The same habit may be triggered from the card, week dots and long-press.
  // Guard the whole dialog + write lifecycle, not only the final API request.
  Future<void> _runHabitAction(
    Habit habit,
    Future<void> Function() action,
  ) async {
    if (!_pendingHabitActions.add(habit.id)) return;
    try {
      await action();
    } finally {
      _pendingHabitActions.remove(habit.id);
    }
  }

  Future<void> _toggleToday(Habit habit) =>
      _runHabitAction(habit, () => _toggleTodayInternal(habit));

  Future<void> _toggleTodayInternal(Habit habit) async {
    if (habit.checkedToday && !habit.allowMultiplePerDay) {
      final confirmed = await FxDialog.confirm(
        context: context,
        title: '取消打卡',
        content: '确定取消今天「${habit.name}」的打卡？连续天数将重新计算。',
        confirmText: '取消打卡',
      );
      if (confirmed != true) return;
      try {
        await _controller.uncheckIn(habit);
        _message('已取消今天的打卡');
      } catch (_) {
        _message('取消打卡失败');
      }
      return;
    }
    int? durationMin;
    int? countValue;
    String? occurredAt;
    String? period;
    var note = '';
    if (habit.showCheckinDialog || habit.recordType == 'count' || habit.recordTimeLabel.isNotEmpty) {
      final value = await HabitCheckinDialog.show(context, habit: habit);
      if (value == null) return;
      durationMin = value['duration_min'] as int?;
      period = value['period']?.toString();
      note = value['note']?.toString() ?? '';
      countValue = value['count_value'] as int?;
      occurredAt = value['occurred_at']?.toString();
    }
    try {
      await _controller.checkIn(
        habit,
        durationMin: durationMin,
        countValue: countValue,
        occurredAt: occurredAt,
        period: period,
        note: note,
      );
      _message('已记录「${habit.name}」');
    } catch (e) {
      _message(e.toString().contains('已打卡') ? '今天已经记录过' : '打卡失败');
    }
  }

  Future<void> _openDetailedCheckin(Habit habit) =>
      _runHabitAction(habit, () => _openDetailedCheckinInternal(habit));

  Future<void> _openDetailedCheckinInternal(Habit habit) async {
    HapticFeedback.mediumImpact();
    if (habit.checkedToday && !habit.allowMultiplePerDay) {
      _message('今天已记录；当前请在历史明细中查看');
      return;
    }
    final value = await HabitCheckinDialog.show(context, habit: habit);
    if (value == null) return;
    try {
      await _controller.checkIn(
        habit,
        durationMin: value['duration_min'] as int?,
        countValue: value['count_value'] as int?,
        occurredAt: value['occurred_at']?.toString(),
        period: value['period']?.toString(),
        note: value['note']?.toString() ?? '',
      );
      HapticFeedback.lightImpact();
      _message('已记录「${habit.name}」');
    } catch (e) {
      _message(e.toString().contains('已打卡') ? '今天已经记录过' : '打卡失败');
    }
  }

  Future<void> _tapWeekDay(Habit habit, DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_sameDay(day, today)) return _toggleToday(habit);
    return _runHabitAction(habit, () => _tapWeekDayInternal(habit, day));
  }

  Future<void> _tapWeekDayInternal(Habit habit, DateTime day) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final key = '${day.year}-${_two(day.month)}-${_two(day.day)}';
    final active = habit.checkedDays.contains(key);
    if (active && !habit.allowMultiplePerDay) {
      _message('历史打卡是事实记录，不在这里修改');
      return;
    }
    if (day.isAfter(today) ||
        day.isBefore(
          DateTime(
            habit.createdAt.year,
            habit.createdAt.month,
            habit.createdAt.day,
          ),
        )) {
      return;
    }
    final detail = await HabitCheckinDialog.show(context, habit: habit, recordDate: day);
    if (detail == null) return;
    try {
      await _controller.checkIn(
        habit,
        date: key,
        durationMin: detail['duration_min'] as int?,
        countValue: detail['count_value'] as int?,
        occurredAt: detail['occurred_at']?.toString(),
        period: detail['period']?.toString(),
        note: detail['note']?.toString() ?? '',
      );
      _message('补卡已记录');
    } catch (e) {
      _message(e.toString().contains('已打卡') ? '该日期已经记录过' : '补卡失败');
    }
  }

  Future<void> _backfill(Habit habit) =>
      _runHabitAction(habit, () => _backfillInternal(habit));

  Future<void> _backfillInternal(Habit habit) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final created = DateTime(
      habit.createdAt.year,
      habit.createdAt.month,
      habit.createdAt.day,
    );
    final yesterday = today.subtract(const Duration(days: 1));
    final initial = yesterday.isBefore(created) ? created : yesterday;
    final date = await showFxDatePicker(
      context: context,
      initialDate: initial,
      firstDate: created.isAfter(today) ? today : created,
      lastDate: today,
      title: '选择补卡日期',
    );
    if (date == null) return;
    final detail = await HabitCheckinDialog.show(context, habit: habit, recordDate: date);
    if (detail == null) return;
    try {
      await _controller.checkIn(
        habit,
        date: '${date.year}-${_two(date.month)}-${_two(date.day)}',
        durationMin: detail['duration_min'] as int?,
        countValue: detail['count_value'] as int?,
        occurredAt: detail['occurred_at']?.toString(),
        period: detail['period']?.toString(),
        note: detail['note']?.toString() ?? '',
      );
      _message('补卡已记录');
    } catch (e) {
      _message(e.toString().contains('已打卡') ? '该日期已经记录过' : '补卡失败');
    }
  }

  Future<void> _delete(Habit habit) =>
      _runHabitAction(habit, () => _deleteInternal(habit));

  Future<void> _deleteInternal(Habit habit) async {
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '删除习惯',
      content: '确定删除「${habit.name}」吗？',
      confirmText: '删除',
      destructive: true,
    );
    if (confirmed != true) return;
    try {
      await _controller.delete(habit);
      if (_expandedHabitId == habit.id) _expandedHabitId = null;
      _message('习惯已删除');
    } catch (_) {
      _message('删除习惯失败');
    }
  }

  Future<void> _toggleExpanded(Habit habit) async {
    if (_expandedHabitId == habit.id) {
      setState(() => _expandedHabitId = null);
      return;
    }
    setState(() => _expandedHabitId = habit.id);
    try {
      await _controller.loadLogs(habit.id);
    } catch (_) {
      _message('近期记录暂时无法获取，可以稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.loading && _controller.habits.isEmpty) {
      return const Center(child: FxCircularProgress());
    }
    final all = _controller.habits;
    final visible = all.where((habit) => switch (_filter) {
      1 => !habit.checkedToday,
      2 => habit.checkedToday,
      _ => true,
    }).toList(growable: false);
    return FxRefresh(
      onRefresh: _controller.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 88),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: SlowlightSpacing.page),
                  if (_controller.error != null) ...[
                    FxCard(
                      padding: const EdgeInsets.all(SlowlightSpacing.xxxl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('习惯加载失败，显示的记录可能不是最新的。',
                              style: SlowlightTypography.secondary(context)),
                          const SizedBox(height: SlowlightSpacing.md),
                          FxButton(
                            label: '重新加载',
                            icon: LucideIcons.refreshCw,
                            variant: FxButtonVariant.outline,
                            size: FxButtonSize.sm,
                            onPressed: _controller.load,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: SlowlightSpacing.page),
                  ],
                  _summaryBar(),
                  const SizedBox(height: SlowlightSpacing.xxxl),
                  if (all.isEmpty && _controller.error == null)
                    FxEmptyState(
                      icon: LucideIcons.repeat2,
                      title: '还没有习惯记录',
                      subtitle: '从一件愿意重复的小事开始。',
                      action: FxButton(
                        label: '创建第一个习惯',
                        icon: LucideIcons.plus,
                        variant: FxButtonVariant.outline,
                        onPressed: _createHabit,
                      ),
                    )
                  else if (all.isNotEmpty && visible.isEmpty)
                    FxEmptyState(
                      icon: LucideIcons.listFilter,
                      title: '当前筛选没有习惯',
                      subtitle: '切换到全部习惯，继续查看记录。',
                      action: FxButton(
                        label: '查看全部习惯',
                        variant: FxButtonVariant.outline,
                        onPressed: () => setState(() => _filter = 0),
                      ),
                    )
                  else
                    ...visible.map(_habitCard),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final theme = Theme.of(context);
    return FxActionBar(
      stackBelow: 280,
      leading: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('习惯', style: SlowlightTypography.pageTitle(context)),
          const SizedBox(height: SlowlightSpacing.xs),
          Text(
            '记录每天的行动，不必追求完美。',
            style: SlowlightTypography.secondary(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        FxButton(
          label: '添加习惯',
          icon: LucideIcons.plus,
          size: FxButtonSize.sm,
          onPressed: _createHabit,
        ),
      ],
    );
  }

  Widget _summaryBar() {
    final theme = Theme.of(context);
    final total = _controller.habits.length;
    final done = _controller.habits.where((habit) => habit.checkedToday).length;
    return FxActionBar(
      stackBelow: 560,
      leading: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: SlowlightSpacing.xl,
        runSpacing: SlowlightSpacing.md,
        children: [
          FxChip(
            label: '$total 个习惯',
            variant: FxChipVariant.outline,
            backgroundColor: fxSubtleSurface(context),
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            borderColor: theme.colorScheme.outline,
            borderRadius: SlowlightRadius.pill,
          ),
          Text(
            '今日已记录 $done/$total',
            style: SlowlightTypography.caption(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        if (total > 0)
          FxSegmented(
            labels: const ['全部', '待记录', '已记录'],
            selectedIndex: _filter,
            onChanged: (index) => setState(() => _filter = index),
            itemKeys: const [
              ValueKey('habits.filter_all'),
              ValueKey('habits.filter_pending'),
              ValueKey('habits.filter_done'),
            ],
          ),
      ],
    );
  }

  Widget _habitCard(Habit habit) {
    final theme = Theme.of(context);
    final expanded = _expandedHabitId == habit.id;
    final color = _parseColor(habit.color);
    return Padding(
      padding: const EdgeInsets.only(bottom: SlowlightSpacing.xl),
      child: FxCard(
        key: ValueKey('habits.card.${habit.id}'),
        padding: const EdgeInsets.all(SlowlightSpacing.xxxl),
        color: fxSurface(context),
        borderRadius: SlowlightRadius.lg,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow:
            theme.brightness == Brightness.light ? AppTheme.cardShadow : null,
        expanded: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final largeText =
                    MediaQuery.textScalerOf(context).scale(1) >= 1.3;
                final narrow = constraints.maxWidth < 270 || largeText;
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _habitHeading(habit, expanded, color),
                      const SizedBox(height: SlowlightSpacing.md),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _todayButton(habit),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: _habitHeading(habit, expanded, color)),
                    const SizedBox(width: SlowlightSpacing.md),
                    _todayButton(habit),
                  ],
                );
              },
            ),
            const SizedBox(height: SlowlightSpacing.xl),
            FxSeparator.horizontal(color: theme.colorScheme.outlineVariant),
            const SizedBox(height: SlowlightSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '最近 7 天',
                  style: SlowlightTypography.caption(context).copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                FxButton(
                  key: ValueKey('habits.details.${habit.id}'),
                  label: expanded ? '收起详情' : '查看详情',
                  icon: expanded
                      ? LucideIcons.chevronUp
                      : LucideIcons.chevronDown,
                  size: FxButtonSize.sm,
                  variant: FxButtonVariant.link,
                  onPressed: () => _toggleExpanded(habit),
                ),
              ],
            ),
            const SizedBox(height: SlowlightSpacing.xs),
            _weekDots(habit, color),
            if (expanded) ...[
              const SizedBox(height: SlowlightSpacing.xxxl),
              FxSeparator.horizontal(color: theme.colorScheme.outlineVariant),
              const SizedBox(height: SlowlightSpacing.xxxl),
              _stats(habit),
              const SizedBox(height: SlowlightSpacing.xxxl),
              _heatmap(habit, color),
              const SizedBox(height: SlowlightSpacing.xxxl),
              Text(
                '最近记录',
                style: SlowlightTypography.fieldLabel(context).copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: SlowlightSpacing.md),
              _logs(habit, color),
              const SizedBox(height: SlowlightSpacing.xxxl),
              FxActionBar(
                stackBelow: 280,
                actions: [
                  FxButton(
                    label: '编辑',
                    icon: LucideIcons.pencil,
                    variant: FxButtonVariant.outline,
                    size: FxButtonSize.sm,
                    onPressed: () => _editHabit(habit),
                  ),
                  FxButton(
                    label: '补卡',
                    icon: LucideIcons.calendarPlus,
                    variant: FxButtonVariant.outline,
                    size: FxButtonSize.sm,
                    onPressed: () => _backfill(habit),
                  ),
                  FxMenu<String>(
                    tooltip: '更多操作',
                    onSelected: (value) {
                      if (value == 'delete') _delete(habit);
                    },
                    itemBuilder: (_) => const [
                      FxMenuItem(
                        value: 'delete',
                        child: Text('删除习惯'),
                      ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: SlowlightSpacing.xl,
                        vertical: SlowlightSpacing.md,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.ellipsis,
                              size: SlowlightIconSize.sm),
                          SizedBox(width: SlowlightSpacing.xs),
                          Text('更多'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _habitHeading(Habit habit, bool expanded, Color color) {
    final theme = Theme.of(context);
    return FxInkWell(
      key: ValueKey('habits.expand.${habit.id}'),
      borderRadius: BorderRadius.circular(SlowlightRadius.md),
      onTap: () => _toggleExpanded(habit),
      onLongPress: () => _openDetailedCheckin(habit),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(SlowlightRadius.md),
              ),
              child: Text(habit.icon,
                  style: SlowlightTypography.cardTitle(context)),
            ),
            const SizedBox(width: SlowlightSpacing.xl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    habit.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SlowlightTypography.cardTitle(context),
                  ),
                  const SizedBox(height: SlowlightSpacing.xs),
                  Text(
                    _habitMeta(habit),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SlowlightTypography.caption(context).copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: SlowlightIconSize.sm,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _todayButton(Habit habit) => FxButton(
        key: ValueKey('habits.today.${habit.id}'),
        label: habit.allowMultiplePerDay ? '新增记录' : habit.checkedToday ? '已记录' : '记录今天',
        icon: habit.checkedToday && !habit.allowMultiplePerDay
            ? LucideIcons.circleCheck
            : LucideIcons.check,
        size: FxButtonSize.sm,
        variant: habit.checkedToday && !habit.allowMultiplePerDay
            ? FxButtonVariant.outline
            : FxButtonVariant.primary,
        onPressed: _pendingHabitActions.contains(habit.id)
            ? null
            : () => _toggleToday(habit),
      );

  Widget _stats(Habit habit) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastSeven = List.generate(7,
        (index) => today.subtract(Duration(days: index)));
    final checked = habit.checkedDays.toSet();
    final recentCount = lastSeven.where((day) =>
        checked.contains('${day.year}-${_two(day.month)}-${_two(day.day)}'))
        .length;
    // 记录事实，不把不同频率的习惯统一当作“完成率”评判。
    final values = [
      ('${habit.streakCount}', '当前连续'),
      ('${habit.checkedDays.length}', '已记录天数'),
      ('$recentCount / 7', '最近七天'),
    ];
    return FxResponsiveFormGrid(
      minColumnWidth: 140,
      maxColumns: 3,
      horizontalGap: SlowlightSpacing.md,
      verticalGap: SlowlightSpacing.md,
      children: values
          .map((item) => _miniStat(item.$1, item.$2))
          .toList(growable: false),
    );
  }

  Widget _miniStat(String value, String label) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: fxSurface(context),
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(SlowlightRadius.md),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: SlowlightTypography.cardTitle(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: SlowlightTypography.caption(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _heatmap(Habit habit, Color color) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    final checked = habit.checkedDays.toSet();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = DateTime(now.year, now.month, 1);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final days = List.generate(35, (i) => start.add(Duration(days: i)));
    final largeText =
        MediaQuery.textScalerOf(
          context,
        ).scale(SlowlightTypography.captionSize) >=
        SlowlightTypography.captionSize * 1.3;
    final cell = largeText ? 28.0 : 19.0;
    final dot = largeText ? 22.0 : 16.0;
    final width = cell * 7;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: labels
                  .map(
                    (label) => SizedBox(
                      width: cell,
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: SlowlightTypography.caption(context),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 3),
            Wrap(
              spacing: cell - dot,
              runSpacing: 3,
              children: days
                  .map((day) {
                    final inMonth = day.month == now.month;
                    final key =
                        '${day.year}-${_two(day.month)}-${_two(day.day)}';
                    final active = checked.contains(key);
                    return Container(
                      width: dot,
                      height: dot,
                      decoration: BoxDecoration(
                        color:
                            active
                                ? color.withValues(alpha: .85)
                                : Theme.of(context).colorScheme.surfaceContainer
                                    .withValues(alpha: inMonth ? 1 : .35),
                        borderRadius: BorderRadius.circular(SlowlightRadius.sm),
                        border:
                            _sameDay(day, today)
                                ? Border.all(color: color, width: 2)
                                : null,
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekDots(Habit habit, Color color) {
    final checked = habit.checkedDays.toSet();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];
    final touch = SlowlightPlatformDensity.usesMobileTouchTargets;
    final target = touch ? SlowlightControlSize.minTouchTarget : 36.0;
    // Android 360dp 不能把 7 天的可点区域缩到不足 44dp。
    // 留出独立横向滚动，不挤压右侧“记录今天”。
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(7, (index) {
          final day = today.subtract(Duration(days: 6 - index));
          final key = '${day.year}-${_two(day.month)}-${_two(day.day)}';
          final active = checked.contains(key);
          return Semantics(
            button: true,
            label: '${day.month}月${day.day}日${active ? '已记录' : '未记录'}',
            child: FxInkWell(
              key: ValueKey('habits.week.${habit.id}.$index'),
              borderRadius: BorderRadius.circular(SlowlightRadius.md),
              onTap: () => _tapWeekDay(habit, day),
              child: SizedBox(
                width: target,
                height: touch ? 54 : 46,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      weekdayLabels[day.weekday - 1],
                      style: SlowlightTypography.caption(context).copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: SlowlightSpacing.xs),
                    Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active ? color : Colors.transparent,
                        border: Border.all(
                          color: active
                              ? color
                              : Theme.of(context).colorScheme.outline,
                          width: _sameDay(day, today) ? 2 : 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Future<void> _removeLog(Habit habit, HabitLog log) =>
      _runHabitAction(habit, () async {
        final confirmed = await FxDialog.confirm(
          context: context,
          title: '撤销这条记录',
          content: '只撤销所选记录，保留当天其他记录。确定吗？',
          confirmText: '撤销记录',
          destructive: true,
        );
        if (confirmed != true) return;
        try {
          await _controller.deleteLog(habit, log.id);
          _message('记录已撤销');
        } catch (error) {
          _message('撤销结果未确认，请重新加载核对：$error');
        }
      });

  Widget _logs(Habit habit, Color color) {
    if (_controller.isLoadingLogs(habit.id)) {
      return const SizedBox(
        height: 28,
        child: Center(child: FxCircularProgress(strokeWidth: 2)),
      );
    }
    final logs = _controller.logsFor(habit.id);
    if (logs.isEmpty) {
      return Text(
        '本月还没有记录。',
        style: SlowlightTypography.caption(
          context,
        ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    final visible = logs.take(3).toList(growable: false);
    return Column(
      children: List.generate(
        visible.length,
        (index) =>
            _logRow(habit, visible[index], color, index == visible.length - 1),
      ),
    );
  }

  Widget _logRow(Habit habit, HabitLog log, Color color, bool last) {
    final theme = Theme.of(context);
    final occurred = log.occurredAt;
    final time = occurred == null ? '时间未记录' : '${_two(occurred.hour)}:${_two(occurred.minute)}';
    final parts = <String>[
      '${log.date.substring(5)} $time',
      if (log.durationMin > 0) '${log.durationMin} 分钟',
      if (log.countValue != null) '${log.countValue} ${habit.recordUnit}',
      if (log.period.isNotEmpty) _periodText(log.period),
    ];
    final today = DateTime.now();
    final todayKey = '${today.year}-${_two(today.month)}-${_two(today.day)}';
    final canCancel = log.date == todayKey;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 18,
          child: Column(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              if (!last)
                Container(
                  width: 1,
                  height: 42,
                  color: color.withValues(alpha: .25),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      parts.join(' · '),
                      style: SlowlightTypography.caption(
                        context,
                      ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (canCancel || habit.allowMultiplePerDay)
                      FxInkWell(
                        onTap: () => habit.allowMultiplePerDay
                            ? _removeLog(habit, log)
                            : _toggleToday(habit),
                        child: Text(
                          '取消',
                          style: SlowlightTypography.caption(
                            context,
                          ).copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                  ],
                ),
                if (log.note.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(log.note, style: SlowlightTypography.secondary(context)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _habitMeta(Habit habit) {
    final parts = <String>[habit.frequencyText];
    if (habit.goalValue > 0) {
      final unit = habit.goalMetric == 'duration' ? '分钟'
          : habit.goalMetric == 'count' ? habit.recordUnit : '次';
      final period = habit.goalPeriod == 'day' ? '今日'
          : habit.goalPeriod == 'week' ? '本周' : '本月';
      parts.add('$period ${habit.goalProgress} / ${habit.goalValue} $unit${habit.goalMet ? ' · 已达标' : ''}');
    }
    if (habit.preferredPeriod.isNotEmpty) {
      parts.add(_periodText(habit.preferredPeriod));
    }
    if (habit.durationMin > 0) {
      parts.add('${habit.durationMin} 分钟');
    }
    if (habit.specificTime.isNotEmpty) {
      parts.add('目标 ${habit.specificTime}');
    }
    return parts.join(' · ');
  }

  String _periodText(String value) => switch (value) {
    'morning' => '☀️ 早晨',
    'afternoon' => '下午',
    'evening' => '傍晚',
    'night' => '🌙 晚间',
    _ => value,
  };

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  String _two(int value) => value.toString().padLeft(2, '0');

  Color _parseColor(String value) {
    try {
      var hex = value.replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return AppTheme.info;
    }
  }
}
