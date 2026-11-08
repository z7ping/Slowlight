import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../controllers/habit_controller.dart';
import '../models/habit.dart';
import '../models/habit_log.dart';
import '../models/habit_schedule_rule.dart';
import '../repositories/habit_repository.dart';
import '../repositories/tag_links_repository.dart';
import '../services/notification_service.dart';
import '../services/api/review_api.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/habit_checkin_flow.dart';
import '../widgets/habit_editor_dialog.dart';

/// Distinguish a habit with a record from the number of log events.
({int total, int recordedToday, int targets, int met}) habitOverviewCounts(
    Iterable<Habit> habits) {
  var total = 0;
  var recordedToday = 0;
  var targets = 0;
  var met = 0;
  for (final habit in habits) {
    total++;
    if (habit.checkedToday) recordedToday++;
    final explicitGoal = habit.goalValue > 0 &&
        const {'day', 'week', 'month'}.contains(habit.goalPeriod);
    final scheduledTarget = !explicitGoal && habit.periodTarget > 0;
    if (!explicitGoal && !scheduledTarget) continue;
    targets++;
    if (explicitGoal
        ? habit.goalMet
        : habit.periodCount >= habit.periodTarget) {
      met++;
    }
  }
  return (total: total, recordedToday: recordedToday,
      targets: targets, met: met);
}

class HabitToolScreen extends StatefulWidget {
  final HabitRepository? repository;
  /// Existing Review API returns a source-backed count of today's log rows.
  final Future<int> Function()? todayLogCountLoader;
  final TagLinksRepository? tagLinksRepository;
  final bool titleProvidedByShell;
  /// Open the existing editor once when the Today empty state requests create.
  final bool createOnOpen;
  /// A search result may request opening one habit in the existing tool.
  final int? focusHabitId;
  final Future<HabitEditorValue?> Function(BuildContext, {Habit? habit})?
      editor;

  const HabitToolScreen({
    super.key,
    this.repository,
    this.todayLogCountLoader,
    this.tagLinksRepository,
    this.editor,
    this.titleProvidedByShell = false,
    this.createOnOpen = false,
    this.focusHabitId,
  });

  @override
  State<HabitToolScreen> createState() => _HabitToolScreenState();
}

class _HabitToolScreenState extends State<HabitToolScreen> with WidgetsBindingObserver {
  late final HabitController _controller;
  late final TagLinksRepository _tagLinks;
  bool _editingHabit = false;
  Timer? _nextSlotRefresh;
  int? _expandedHabitId;
  int? _pendingFocusHabitId;
  final GlobalKey _focusedHabitKey = GlobalKey(debugLabel: '搜索习惯定位');
  int _filter = 0; // 全部 / 待记录 / 已记录
  // Keep same-width action slots across recorded and pending habits.
  static const double _todayActionWidth = 104;
  static const double _mobileTodayActionWidth = 120;
  final Set<int> _pendingHabitActions = <int>{};
  final Set<int> _allLogsVisible = <int>{};
  HabitEditorValue? _creationDraft;
  final Map<int, HabitEditorValue> _editDrafts = {};
  int? _todayLogCount;
  int _todayLogRevision = 0;
  int _habitReloadRevision = 0;

  Future<int> _readTodayLogCount() async {
    final int count;
    if (widget.todayLogCountLoader != null) {
      count = await widget.todayLogCountLoader!();
    } else {
      final review = await ReviewApi.getTodayReview();
      final facts = review['facts'];
      final value = facts is Map ? facts['habit_checked'] : null;
      if (value is! int) {
        throw const FormatException('今日习惯日志计数不可用');
      }
      count = value;
    }
    if (count < 0) {
      throw const FormatException('今日习惯日志计数无效');
    }
    return count;
  }

  Future<void> _refreshTodayLogCount() async {
    final revision = ++_todayLogRevision;
    if (!mounted) return;
    setState(() => _todayLogCount = null);
    try {
      final count = await _readTodayLogCount();
      if (mounted && revision == _todayLogRevision) {
        setState(() => _todayLogCount = count);
      }
    } catch (_) {
      // Unknown is not zero; do not reuse an earlier count after a failed read.
      if (mounted && revision == _todayLogRevision) {
        setState(() => _todayLogCount = null);
      }
    }
  }

  Future<void> _reloadHabitsAndSummary() async {
    final revision = ++_habitReloadRevision;
    await _controller.load();
    if (!mounted || revision != _habitReloadRevision) return;
    if (_controller.error != null) {
      ++_todayLogRevision;
      setState(() => _todayLogCount = null);
    } else if (_controller.habits.isEmpty) {
      ++_todayLogRevision;
      setState(() => _todayLogCount = 0);
    } else {
      await _refreshTodayLogCount();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tagLinks = widget.tagLinksRepository ?? TagLinksRepository();
    _controller = HabitController(repository: widget.repository)
      ..addListener(_onChanged);
    _pendingFocusHabitId = widget.focusHabitId;
    unawaited(_reloadHabitsAndSummary());
    if (widget.createOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _createHabit();
      });
    }
  }

  @override
  void dispose() {
    ++_todayLogRevision;
    ++_habitReloadRevision;
    WidgetsBinding.instance.removeObserver(this);
    _nextSlotRefresh?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HabitToolScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusHabitId != null &&
        widget.focusHabitId != oldWidget.focusHabitId) {
      _pendingFocusHabitId = widget.focusHabitId;
      _focusRequestedHabit();
    }
  }

  void _focusRequestedHabit() {
    final id = _pendingFocusHabitId;
    if (id == null || !_controller.habits.any((habit) => habit.id == id)) {
      return;
    }
    _pendingFocusHabitId = null;
    _filter = 0;
    _expandedHabitId = id;
    // Reuse the same logs and details as an ordinary card expansion.
    unawaited(_controller.loadLogs(id).catchError((Object _) {
      _message('近期记录暂时无法获取，可以稍后重试');
    }));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _focusedHabitKey.currentContext;
      if (!mounted || targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.12,
        duration: MediaQuery.disableAnimationsOf(targetContext)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _onChanged() {
    if (!mounted) return;
    _focusRequestedHabit();
    setState(() {});
    _refreshAtNextSlot();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reloadHabitsAndSummary());
      NotificationService().scheduleHabitReminders().catchError((Object _) {});
    }
  }

  void _refreshAtNextSlot() {
    _nextSlotRefresh?.cancel();
    final now=DateTime.now();
    DateTime? next;
    for (final habit in _controller.habits) {
      if (habit.scheduleRule.isEmpty) continue;
      final rule=HabitScheduleRule.fromJson(habit.scheduleRule,
          legacyFrequency:habit.frequency);
      final times=rule.nextAfter(now,count:1);
      final candidate=times.isNotEmpty ? times.first :
          rule.kind=='goal' ? DateTime(now.year,now.month,now.day+1) : null;
      if(candidate!=null && (next==null || candidate.isBefore(next)))next=candidate;
    }
    if(next==null)return;
    final delay=next.difference(now)+const Duration(seconds:2);
    _nextSlotRefresh=Timer(delay, () { if(mounted) unawaited(_reloadHabitsAndSummary()); });
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
      Future<void> save(HabitEditorValue value) async {
        final created = await _controller.create(
          name: value.name,
          icon: value.icon,
          color: value.color,
          frequency: value.frequency,
          scheduleRule: value.scheduleRule,
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
        _creationDraft = null;
        if (value.tagIds != null &&
            value.tagIds!.isNotEmpty &&
            !await _saveHabitTags(
                created.id, List<int>.from(value.tagIds!), '创建')) {
          return;
        }
        _message('习惯已创建');
        try { await NotificationService().scheduleHabitReminders(); }
        catch (_) { _message('习惯已保存，但提醒调度暂时失败'); }
      }

      if (widget.editor == null) {
        await HabitEditorDialog.show(context,
            onSubmit: save,
            initialValue: _creationDraft,
            onUnconfirmed: (value) => _creationDraft = value);
      } else {
        final value = await widget.editor!(context);
        if (value != null && mounted) await save(value);
      }
    } catch (e) {
      _message('创建结果未确认，请先在习惯列表核对，避免重复创建：$e');
    } finally {
      _editingHabit = false;
    }
  }

  Future<void> _editHabit(Habit habit) async {
    if (_editingHabit) return;
    _editingHabit = true;
    try {
      Future<void> save(HabitEditorValue value) async {
        await _controller.update(
          habit,
          name: value.name,
          icon: value.icon,
          color: value.color,
          frequency: value.frequency,
          scheduleRule: value.scheduleRule,
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
        _editDrafts.remove(habit.id);
        if (value.tagIds != null &&
            !await _saveHabitTags(
                habit.id, List<int>.from(value.tagIds!), '更新')) {
          return;
        }
        _message('习惯已更新');
        try { await NotificationService().scheduleHabitReminders(); }
        catch (_) { _message('习惯已更新，但提醒调度暂时失败'); }
      }

      if (widget.editor == null) {
        await HabitEditorDialog.show(context,
            habit: habit,
            onSubmit: save,
            initialValue: _editDrafts[habit.id],
            onUnconfirmed: (value) => _editDrafts[habit.id] = value);
      } else {
        final value = await widget.editor!(context, habit: habit);
        if (value != null && mounted) await save(value);
      }
    } catch (e) {
      _message('更新结果未确认，请先查看习惯详情再重试：$e');
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

  // The V3 schedule is authoritative for goal habits: the legacy flat
  // allow_multiple_per_day field may differ after an older edit or sync.
  bool _allowsMultipleToday(Habit habit) {
    if (habit.scheduleRule.isEmpty) return habit.allowMultiplePerDay;
    final rule = HabitScheduleRule.fromJson(
      habit.scheduleRule, legacyFrequency: habit.frequency,
    );
    return rule.kind == 'goal' ? rule.sameDayMultiple : habit.allowMultiplePerDay;
  }

  Future<void> _toggleToday(Habit habit) =>
      _runHabitAction(habit, () => _toggleTodayInternal(habit));

  Future<void> _toggleTodayInternal(Habit habit) async {
    if (habit.checkedToday && !_allowsMultipleToday(habit) && habit.canCheckIn != true) {
      final confirmed = await FxDialog.confirm(
        context: context,
        title: '取消打卡',
        content: '确定取消今天「${habit.name}」的打卡？连续天数将重新计算。',
        confirmText: '取消打卡',
      );
      if (confirmed != true) return;
      try {
        await _controller.uncheckIn(habit);
        unawaited(_refreshTodayLogCount());
        _message('已取消今天的打卡');
      } catch (_) {
        // The write may have committed before the response was lost.
        unawaited(_refreshTodayLogCount());
        _message('取消打卡失败');
      }
      return;
    }
    if (habit.scheduleRule.isNotEmpty && habit.canCheckIn == false) {
      _message('当前没有可记录的计划时点，或今天已有记录');
      return;
    }
    await _record(habit);
  }

  Future<void> _openDetailedCheckin(Habit habit) =>
      _runHabitAction(habit, () async {
        HapticFeedback.mediumImpact();
        if (habit.checkedToday && !_allowsMultipleToday(habit) && habit.canCheckIn != true) {
          _message('今天已记录；请在历史明细中查看');
          return;
        }
        if (habit.scheduleRule.isNotEmpty && habit.canCheckIn == false) {
          _message('当前没有可记录的计划时点');
          return;
        }
        await _record(habit, detailed: true);
      });

  Future<void> _record(Habit habit,
      {bool detailed = false, DateTime? date}) async {
    var attempted = false;
    final saved = await recordHabit(
      context,
      habit: habit,
      detailed: detailed,
      recordDate: date,
      submit: (value) async {
        attempted = true;
        await _controller.checkIn(
          habit,
          date: date == null
              ? null
              : '${date.year}-${_two(date.month)}-${_two(date.day)}',
          durationMin: value['duration_min'] as int?,
          countValue: value['count_value'] as int?,
          occurredAt: value['occurred_at'] as String?,
          period: value['period'] as String?,
          note: value['note'] as String? ?? '',
          clientKey: value['client_key'] as String?,
        );
      },
    );
    if (attempted) {
      // Even a failed ACK may have committed remotely. Re-read the source
      // instead of retaining an old count as though no write happened.
      unawaited(_refreshTodayLogCount());
    }
    if (saved) {
      _message(date == null ? '已记录「${habit.name}」' : '补卡已记录');
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
    final rule = habit.scheduleRule.isEmpty ? null : HabitScheduleRule.fromJson(
      habit.scheduleRule, legacyFrequency: habit.frequency,
    );
    if (rule?.kind == 'interval' && rule?.unit == 'hour') {
      _message('小时计划需要具体发生时点，不能只按日期补记');
      return;
    }
    final anchor = rule?.anchor;
    final earliest = anchor != null && anchor.isAfter(created) ? anchor : created;
    if (earliest.isAfter(today)) {
      _message('尚未到达习惯起算日期');
      return;
    }
    final yesterday = today.subtract(const Duration(days: 1));
    final initial = yesterday.isBefore(earliest) ? earliest : yesterday;
    final date = await showFxDatePicker(
      context: context,
      initialDate: initial,
      firstDate: earliest,
      lastDate: today,
      title: '选择补卡日期',
    );
    if (date == null) return;
    await _record(habit, detailed: true, date: date);
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
    final visible = all
        .where((habit) => switch (_filter) {
              1 => !habit.checkedToday,
              2 => habit.checkedToday,
              _ => true,
            })
        .toList(growable: false);
    return FxRefresh(
      onRefresh: _reloadHabitsAndSummary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: SlowlightPageInsets.scroll(context, bottom: 88),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.titleProvidedByShell) ...[
                    _header(),
                    const SizedBox(height: SlowlightSpacing.xl),
                  ],
                  if (_controller.error != null) ...[
                    FxCard(
                      padding: const EdgeInsets.all(SlowlightSpacing.xl),
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
                            onPressed: _reloadHabitsAndSummary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: SlowlightSpacing.xl),
                  ],
                  _summaryBar(),
                  if (all.isNotEmpty) ...[
                    const SizedBox(height: SlowlightSpacing.md),
                    _filters(),
                  ],
                  const SizedBox(height: SlowlightSpacing.xl),
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
        _addButton(),
      ],
    );
  }

  Widget _summaryBar() {
    final theme = Theme.of(context);
    final caption = SlowlightTypography.caption(context).copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (_controller.error != null) {
      return FxActionBar(
        stackBelow: 280,
        leading: Text('习惯概况待核对', style: caption),
        actions: [if (widget.titleProvidedByShell) _addButton()],
      );
    }
    final counts = habitOverviewCounts(_controller.habits);
    final records = _todayLogCount == null
        ? '今日日志待核对'
        : '今日日志 ${_todayLogCount} 条';
    final period = counts.targets == 0
        ? '本期达标 —'
        : '本期达标 ${counts.met}/${counts.targets}';
    if (SlowlightPlatformDensity.usesMobileTouchTargets) {
      return FxActionBar(
        stackBelow: 280,
        leading: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${counts.total} 个习惯 · 今日 ${counts.recordedToday} 个有记录',
                style: caption),
            const SizedBox(height: SlowlightSpacing.xs),
            Text('$records · $period', style: caption),
          ],
        ),
        actions: [if (widget.titleProvidedByShell) _addButton()],
      );
    }
    return FxActionBar(
      stackBelow: 560,
      leading: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: SlowlightSpacing.xl,
        runSpacing: SlowlightSpacing.md,
        children: [
          FxChip(
            label: '${counts.total} 个习惯',
            variant: FxChipVariant.outline,
            backgroundColor: fxSubtleSurface(context),
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            borderColor: theme.colorScheme.outline,
            borderRadius: SlowlightRadius.pill,
          ),
          Text('今日 ${counts.recordedToday} 个有记录', style: caption),
          Text(records, style: caption),
          Text(period, style: caption),
        ],
      ),
      actions: [if (widget.titleProvidedByShell) _addButton()],
    );
  }

  Widget _addButton() => FxButton(
        label: '添加习惯',
        icon: LucideIcons.plus,
        size: FxButtonSize.sm,
        variant: SlowlightPlatformDensity.usesMobileTouchTargets
            ? FxButtonVariant.outline
            : FxButtonVariant.primary,
        onPressed: _createHabit,
      );

  Widget _filters() {
    final total = _controller.habits.length;
    final mobile = SlowlightPlatformDensity.usesMobileTouchTargets;
    if (total == 0) return const SizedBox.shrink();
    final segments = FxSegmented(
      labels: mobile
          ? const ['全部', '今日未记录', '今日有记录']
          : const ['全部', '待记录', '已记录'],
      selectedIndex: _filter,
      onChanged: (index) => setState(() => _filter = index),
      itemKeys: const [
        ValueKey('habits.filter_all'),
        ValueKey('habits.filter_pending'),
        ValueKey('habits.filter_done'),
      ],
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: mobile
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: segments,
            )
          : segments,
    );
  }

  Widget _habitCard(Habit habit) {
    final theme = Theme.of(context);
    final expanded = _expandedHabitId == habit.id;
    final color = _parseColor(habit.color);
    final mobile = SlowlightPlatformDensity.usesMobileTouchTargets;
    return Padding(
      key: habit.id == widget.focusHabitId ? _focusedHabitKey : null,
      padding: const EdgeInsets.only(bottom: SlowlightSpacing.md),
      child: FxCard(
        key: ValueKey('habits.card.${habit.id}'),
        padding: EdgeInsets.symmetric(
          horizontal: SlowlightSpacing.xl,
          vertical: mobile ? SlowlightSpacing.md : SlowlightSpacing.xl,
        ),
        color: fxSurface(context),
        borderRadius: SlowlightRadius.lg,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        expanded: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final largeText =
                    MediaQuery.textScalerOf(context).scale(1) >= 1.3;
                final narrow = constraints.maxWidth < 270 || largeText;
                final actionWidth = (SlowlightPlatformDensity.usesMobileTouchTargets
                        ? _mobileTodayActionWidth
                        : _todayActionWidth) *
                    MediaQuery.textScalerOf(context).scale(1);
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _habitHeading(habit, color),
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
                    Expanded(child: _habitHeading(habit, color)),
                    const SizedBox(width: SlowlightSpacing.md),
                    SizedBox(
                      width: actionWidth,
                      child: _todayButton(habit, expanded: true),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: SlowlightSpacing.xs),
            LayoutBuilder(builder: (context, constraints) {
              final details = FxButton(
                key: ValueKey('habits.details.${habit.id}'),
                label: mobile
                    ? (expanded ? '收起' : '详情')
                    : (expanded ? '收起详情' : '查看详情'),
                icon:
                    expanded ? LucideIcons.chevronUp : LucideIcons.chevronRight,
                size: FxButtonSize.sm,
                variant: FxButtonVariant.link,
                onPressed: () => _toggleExpanded(habit),
              );
              final label = Text('最近 7 天',
                  style: SlowlightTypography.caption(context).copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ));
              final scale = MediaQuery.textScalerOf(context).scale(1);
              if (mobile) {
                // One compact line in the master prototype. Wrap at large
                // accessibility scale rather than shrinking or clipping.
                return Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: SlowlightSpacing.md,
                  children: [label, _weekDots(habit, color), details],
                );
              }
              if (constraints.maxWidth >= 460 * scale) {
                return Row(children: [
                  label,
                  const SizedBox(width: SlowlightSpacing.md),
                  Expanded(child: _weekDots(habit, color)),
                  details,
                ]);
              }
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FxActionBar(
                        leading: label, actions: [details], stackBelow: 0),
                    _weekDots(habit, color),
                  ]);
            }),
            AnimatedSize(
              key: ValueKey('habits.motion.${habit.id}'),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: SlowlightSpacing.xl),
                        FxSeparator.horizontal(
                  margin: EdgeInsets.zero,
                  color: theme.colorScheme.outlineVariant),
              const SizedBox(height: SlowlightSpacing.xl),
              _stats(habit),
              if (habit.goalHistory.isNotEmpty) ...[
                const SizedBox(height: SlowlightSpacing.xs),
                Text(_goalRevisionSummary(habit),
                    style: SlowlightTypography.caption(context)),
              ],
              const SizedBox(height: SlowlightSpacing.xl),
              FxResponsiveFormGrid(
                minColumnWidth: 240,
                children: [
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('本月记录',
                            style: SlowlightTypography.fieldLabel(context)),
                        const SizedBox(height: SlowlightSpacing.md),
                        _heatmap(habit, color),
                      ]),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('最近记录',
                            style: SlowlightTypography.fieldLabel(context)),
                        const SizedBox(height: SlowlightSpacing.md),
                        _logs(habit, color),
                      ]),
                ],
              ),
              const SizedBox(height: SlowlightSpacing.xl),
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
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _habitHeading(Habit habit, Color color) {
    final theme = Theme.of(context);
    final mobile = SlowlightPlatformDensity.usesMobileTouchTargets;
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
              key: ValueKey('habits.icon.${habit.id}'),
              width: mobile ? 32 : 40,
              height: mobile ? 32 : 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: mobile ? fxSubtleSurface(context) : color.withValues(alpha: .12),
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
          ],
        ),
      ),
    );
  }

  Widget _todayButton(Habit habit, {bool expanded = false}) {
    final canAppend = _allowsMultipleToday(habit);
    final completed = habit.checkedToday &&
        !canAppend &&
        habit.canCheckIn != true;
    final theme = Theme.of(context);
    final mobile = SlowlightPlatformDensity.usesMobileTouchTargets;
    // Keep the action subtle in both themes while using the existing
    // success semantic color instead of a page-specific color constant.
    final actionColor = Color.lerp(
      AppTheme.success,
      theme.colorScheme.onSurface,
      theme.brightness == Brightness.dark ? .08 : .38,
    )!;
    return FxButton(
      key: ValueKey('habits.today.${habit.id}'),
      label: canAppend || (habit.checkedToday && habit.canCheckIn == true)
          ? '新增记录'
          : habit.checkedToday
              ? '已记录'
              : '记录今天',
      icon: completed ? LucideIcons.circleCheck : LucideIcons.check,
      size: FxButtonSize.sm,
      expanded: expanded,
      variant: mobile ? FxButtonVariant.outline : FxButtonVariant.secondary,
      foregroundColor: mobile
          ? null
          : completed
              ? theme.colorScheme.onSurfaceVariant
              : actionColor,
      onPressed: _pendingHabitActions.contains(habit.id)
          ? null
          : () => _toggleToday(habit),
    );
  }

  Widget _stats(Habit habit) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastSeven =
        List.generate(7, (index) => DateTime(today.year, today.month, today.day - index));
    final checked = habit.checkedDays.toSet();
    final recentCount = lastSeven
        .where((day) =>
            checked.contains('${day.year}-${_two(day.month)}-${_two(day.day)}'))
        .length;
    // The summary API only supplies seven-day dots. All-time statistics
    // must come from the actual untruncated history after it has loaded.
    final historyKnown = _controller.hasLoadedLogs(habit.id);
    final historyDays = historyKnown
        ? _controller.logsFor(habit.id).map((log) => log.date).toSet().length
        : null;
    // 记录事实，不把不同频率的习惯统一当作“完成率”评判。
    final values = [
      ('${habit.streakCount}', '当前连续'),
      (historyDays?.toString() ?? '待核对', '已记录天数'),
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
    if (!_controller.hasLoadedLogs(habit.id)) {
      return Text('本月记录待读取',
          style: SlowlightTypography.caption(context));
    }
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    final checked = _controller.logsFor(habit.id)
        .map((log) => log.date).toSet();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = DateTime(now.year, now.month, 1);
    final leadingDays = first.weekday - 1;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    // Months requiring six calendar rows must not silently lose their
    // final dates (e.g. November 2026 ends on a sixth-row Monday).
    final gridLength = ((leadingDays + daysInMonth + 6) ~/ 7) * 7;
    final start = DateTime(now.year, now.month, 1 - leadingDays);
    final days = List.generate(gridLength,
        (index) => DateTime(start.year, start.month, start.day + index));
    final largeText = MediaQuery.textScalerOf(
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
              children: days.map((day) {
                final inMonth = day.month == now.month;
                final key = '${day.year}-${_two(day.month)}-${_two(day.day)}';
                final active = checked.contains(key);
                return Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: active
                        ? color.withValues(alpha: .85)
                        : Theme.of(context)
                            .colorScheme
                            .surfaceContainer
                            .withValues(alpha: inMonth ? 1 : .35),
                    borderRadius: BorderRadius.circular(SlowlightRadius.sm),
                    border: _sameDay(day, today)
                        ? Border.all(color: color, width: 2)
                        : null,
                  ),
                );
              }).toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekDots(Habit habit, Color color) {
    final checked = habit.checkedDays.toSet();
    if (SlowlightPlatformDensity.usesMobileTouchTargets) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final scheme = Theme.of(context).colorScheme;
      // The approved Android overview uses 7px read-only dots. Details
      // remains the adjacent full-size action, never these fact markers.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(7, (index) {
          final day = DateTime(today.year, today.month, today.day - (6 - index));
          final key = '${day.year}-${_two(day.month)}-${_two(day.day)}';
          final active = checked.contains(key) ||
              (_sameDay(day, today) && habit.checkedToday);
          return Padding(
            padding: EdgeInsets.only(
              right: index == 6 ? 0 : SlowlightSpacing.xs,
            ),
            child: Semantics(
              label: '${day.month}月${day.day}日${active ? '有记录' : '无记录'}',
              child: Container(
                key: ValueKey('habits.week.${habit.id}.$index'),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? scheme.primary : fxSubtleSurface(context),
                ),
              ),
            ),
          );
        }),
      );
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];
    final touch = SlowlightPlatformDensity.usesMobileTouchTargets;
    final target = touch ? SlowlightControlSize.minTouchTarget : 36.0;
    // 七日点阵只展示历史事实；补记与撤销由显式入口处理。
    // Android 窄屏允许水平阅读，避免挤压七日信息。
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(7, (index) {
          final day = today.subtract(Duration(days: 6 - index));
          final key = '${day.year}-${_two(day.month)}-${_two(day.day)}';
          final active = checked.contains(key);
          return Semantics(
            label: '${day.month}月${day.day}日${active ? '已记录' : '未记录'}',
            child: Container(
              key: ValueKey('habits.week.${habit.id}.$index'),
              width: target,
              constraints: BoxConstraints(
                minHeight: touch ? 48 : SlowlightControlSize.minTouchTarget,
              ),
              padding:
                  const EdgeInsets.symmetric(vertical: SlowlightSpacing.xs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
        var writeAcknowledged = false;
        try {
          await _controller.deleteLog(habit, log.id);
          writeAcknowledged = true;
        } catch (_) {
          // A lost deletion ACK is not proof that the record still exists.
          // Read history instead of issuing another destructive request.
        }
        final removed = await _controller.verifyLogRemoval(habit.id, log.id);
        if (!mounted) return;
        unawaited(_refreshTodayLogCount());
        if (removed == null) {
          _message('撤销结果未确认，无法核对最新记录，请稍后重试');
        } else if (!removed) {
          _message(writeAcknowledged
              ? '撤销请求已提交，记录仍在列表中，请稍后核对'
              : '撤销未确认，记录仍在列表中');
        } else {
          _message('记录已撤销');
        }
      });

  Widget _logs(Habit habit, Color color) {
    final loading = _controller.isLoadingLogs(habit.id);
    final logs = _controller.logsFor(habit.id);
    final error = _controller.logErrorFor(habit.id);
    // A background refresh does not erase the confirmed history. Mark it
    // as being checked until the coalesced post-write read has settled.
    if (loading && logs.isEmpty) {
      return const SizedBox(
        height: 28,
        child: Center(child: FxCircularProgress(strokeWidth: 2)),
      );
    }
    if (logs.isEmpty && error == null) {
      return Text(
        '还没有记录。',
        style: SlowlightTypography.caption(
          context,
        ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    final showAll = _allLogsVisible.contains(habit.id);
    final visible = (showAll ? logs : logs.take(3)).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading) ...[
          Text('正在核对记录，以下为上次已读取的内容',
              style: SlowlightTypography.caption(context)),
          const SizedBox(height: SlowlightSpacing.xs),
        ],
        if (error != null) ...[
          Text(logs.isEmpty ? '记录暂时无法加载，当前数量未知。' : '记录刷新失败，以下为上次加载的数据。'),
          FxButton(
              label: '重试加载记录',
              variant: FxButtonVariant.outline,
              onPressed: () => _controller.loadLogs(habit.id)),
          const SizedBox(height: SlowlightSpacing.md),
        ],
        ...List.generate(
          visible.length,
          (index) => _logRow(
              habit, visible[index], color, index == visible.length - 1),
        ),
        if (logs.length > 3)
          FxButton(
            key: ValueKey('habits.logs.all.${habit.id}'),
            label: showAll ? '收起记录' : '查看全部 ${logs.length} 条记录',
            variant: FxButtonVariant.link,
            onPressed: () => setState(() {
              if (showAll) {
                _allLogsVisible.remove(habit.id);
              } else {
                _allLogsVisible.add(habit.id);
              }
            }),
          ),
      ],
    );
  }

  Widget _logRow(Habit habit, HabitLog log, Color color, bool last) {
    final theme = Theme.of(context);
    final occurred = log.occurredAt;
    final time = occurred == null
        ? '时间未记录'
        : '${_two(occurred.hour)}:${_two(occurred.minute)}';
    final parts = <String>[
      '${log.date.substring(5)} $time',
      if (log.durationMin > 0) '${log.durationMin} 分钟',
      if (log.countValue != null) '${log.countValue} ${habit.recordUnit}',
      if (log.period.isNotEmpty) _periodText(log.period),
    ];
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
                    // An individual history row must cancel its own log ID,
                    // never a day-level toggle that could add a new slot.
                    FxButton(
                      key: ValueKey('habits.logs.cancel.${log.id}'),
                      label: '撤销',
                      size: FxButtonSize.sm,
                      variant: FxButtonVariant.ghost,
                      onPressed: () => _removeLog(habit, log),
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

  String _goalRevisionSummary(Habit habit) {
    final versions = habit.goalHistory.reversed.take(3).toList().reversed;
    final summaries = versions.map((row) {
      final value = row['goal_value'] ?? '未知';
      final metric = row['goal_metric'] == 'duration'
          ? '分钟' : row['goal_metric'] == 'count'
              ? (row['record_unit']?.toString() ?? habit.recordUnit) : '次';
      return 'v${row['revision'] ?? '?'} $value$metric';
    }).join(' → ');
    return '保存的目标版本 ${habit.goalHistory.length} 条 · $summaries';
  }

  String _habitMeta(Habit habit) {
    final parts = <String>[habit.frequencyText];
    if (habit.goalValue > 0) {
      final unit = habit.goalMetric == 'duration'
          ? '分钟'
          : habit.goalMetric == 'count'
              ? habit.recordUnit
              : '次';
      final period = habit.goalPeriod == 'day'
          ? '今日'
          : habit.goalPeriod == 'week'
              ? '本周'
              : '本月';
      parts.add(
          '$period ${habit.goalProgress} / ${habit.goalValue} $unit${habit.goalMet ? ' · 已达标' : ''}');
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
