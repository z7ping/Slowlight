import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../controllers/habit_controller.dart';
import '../models/habit.dart';
import '../models/habit_log.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/habit_checkin_dialog.dart';
import '../widgets/habit_editor_dialog.dart';

class HabitToolScreen extends StatefulWidget {
  const HabitToolScreen({super.key});

  @override
  State<HabitToolScreen> createState() => _HabitToolScreenState();
}

class _HabitToolScreenState extends State<HabitToolScreen> {
  late final HabitController _controller;
  int? _expandedHabitId;

  @override
  void initState() {
    super.initState();
    _controller = HabitController()..addListener(_onChanged);
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

  Future<void> _createHabit() async {
    final value = await HabitEditorDialog.show(context);
    if (value == null) return;
    try {
      await _controller.create(
        name: value.name,
        icon: value.icon,
        color: value.color,
        frequency: value.frequency,
        targetDays: value.targetDays,
        systemTagId: value.systemTagId,
        preferredPeriod: value.preferredPeriod,
        durationMin: value.durationMin,
        generateTask: value.generateTask,
        showCheckinDialog: value.showCheckinDialog,
        specificTime: value.specificTime,
        reminderAt: value.reminderAt,
      );
      _message('习惯已创建');
    } catch (_) {
      _message('创建习惯失败');
    }
  }

  Future<void> _editHabit(Habit habit) async {
    final value = await HabitEditorDialog.show(context, habit: habit);
    if (value == null) return;
    try {
      await _controller.update(
        habit,
        name: value.name,
        icon: value.icon,
        color: value.color,
        frequency: value.frequency,
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
      _message('习惯已更新');
    } catch (_) {
      _message('更新习惯失败');
    }
  }

  Future<void> _toggleToday(Habit habit) async {
    if (habit.checkedToday) {
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
    String? period;
    var note = '';
    if (habit.showCheckinDialog) {
      final value = await HabitCheckinDialog.show(context, habit: habit);
      if (value == null) return;
      durationMin = value['duration_min'] as int?;
      period = value['period']?.toString();
      note = value['note']?.toString() ?? '';
    }
    try {
      await _controller.checkIn(
        habit,
        durationMin: durationMin,
        period: period,
        note: note,
      );
      _message('已记录「${habit.name}」');
    } catch (e) {
      _message(e.toString().contains('已打卡') ? '今天已经记录过' : '打卡失败');
    }
  }

  Future<void> _openDetailedCheckin(Habit habit) async {
    HapticFeedback.mediumImpact();
    if (habit.checkedToday) {
      _message('今天已记录；当前暂不支持编辑打卡详情');
      return;
    }
    final value = await HabitCheckinDialog.show(context, habit: habit);
    if (value == null) return;
    try {
      await _controller.checkIn(
        habit,
        durationMin: value['duration_min'] as int?,
        period: value['period']?.toString(),
        note: value['note']?.toString() ?? '',
      );
      HapticFeedback.lightImpact();
      _message('已记录「${habit.name}」');
    } catch (e) {
      _message(e.toString().contains('已打卡') ? '今天已经记录过' : '打卡失败');
    }
  }

  Future<void> _tapWeekDay(Habit habit, DateTime day) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final key = '${day.year}-${_two(day.month)}-${_two(day.day)}';
    final active = habit.checkedDays.contains(key);
    if (_sameDay(day, today)) return _toggleToday(habit);
    if (active) {
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
    final detail = await HabitCheckinDialog.show(context, habit: habit);
    if (detail == null) return;
    try {
      await _controller.checkIn(
        habit,
        date: key,
        durationMin: detail['duration_min'] as int?,
        period: detail['period']?.toString(),
        note: detail['note']?.toString() ?? '',
      );
      _message('补卡已记录');
    } catch (e) {
      _message(e.toString().contains('已打卡') ? '该日期已经记录过' : '补卡失败');
    }
  }

  Future<void> _backfill(Habit habit) async {
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
    final detail = await HabitCheckinDialog.show(context, habit: habit);
    if (detail == null) return;
    try {
      await _controller.checkIn(
        habit,
        date: '${date.year}-${_two(date.month)}-${_two(date.day)}',
        durationMin: detail['duration_min'] as int?,
        period: detail['period']?.toString(),
        note: detail['note']?.toString() ?? '',
      );
      _message('补卡已记录');
    } catch (e) {
      _message(e.toString().contains('已打卡') ? '该日期已经记录过' : '补卡失败');
    }
  }

  Future<void> _delete(Habit habit) async {
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
    await _controller.loadLogs(habit.id);
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.loading && _controller.habits.isEmpty) {
      return const Center(child: FxCircularProgress());
    }
    if (_controller.error != null && _controller.habits.isEmpty) {
      return Center(
        child: FxButton(
          label: '重试',
          variant: FxButtonVariant.secondary,
          onPressed: _controller.load,
        ),
      );
    }
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
                  const SizedBox(height: 14),
                  if (_controller.habits.isEmpty)
                    FxEmptyState(
                      emoji: '🌱',
                      title: '还没有习惯记录',
                      subtitle: '从一个小习惯开始，比如每天喝一杯水',
                      action: FxButton(
                        label: '添加第一个习惯',
                        variant: FxButtonVariant.outline,
                        size: FxButtonSize.sm,
                        onPressed: _createHabit,
                      ),
                    )
                  else
                    ..._controller.habits.map(_habitCard),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final stacked = constraints.maxWidth < 420 || scale >= 1.6;
        final count = FxChip(
          label: '${_controller.habits.length} 个习惯',
          variant: FxChipVariant.outline,
          backgroundColor: fxSubtleSurface(context),
          foregroundColor: theme.colorScheme.onSurfaceVariant,
          borderColor: theme.colorScheme.outline,
          borderRadius: 999,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        );
        final action = FxButton(
          label: '添加习惯',
          icon: LucideIcons.plus,
          size: FxButtonSize.sm,
          onPressed: _createHabit,
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerLeft, child: count),
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerRight, child: action),
            ],
          );
        }
        return Row(children: [count, const Spacer(), action]);
      },
    );
  }

  Widget _habitCard(Habit habit) {
    final theme = Theme.of(context);
    final expanded = _expandedHabitId == habit.id;
    final color = _parseColor(habit.color);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FxCard(
        padding: const EdgeInsets.fromLTRB(13, 13, 14, 13),
        color: fxSurface(context),
        borderRadius: SlowlightRadius.lg,
        border: Border(
          left: BorderSide(color: color, width: 3),
          top: BorderSide(color: theme.colorScheme.outline),
          right: BorderSide(color: theme.colorScheme.outline),
          bottom: BorderSide(color: theme.colorScheme.outline),
        ),
        boxShadow:
            theme.brightness == Brightness.light ? AppTheme.cardShadow : null,
        expanded: true,
        child: Column(
          children: [
            FxInkWell(
              borderRadius: BorderRadius.circular(SlowlightRadius.md),
              onTap: () => _toggleExpanded(habit),
              onLongPress: () => _openDetailedCheckin(habit),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scale = MediaQuery.textScalerOf(context).scale(1);
                    final showWeek =
                        !expanded && constraints.maxWidth >= 560 && scale < 1.6;
                    return Row(
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
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                habit.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: SlowlightTypography.secondary(
                                  context,
                                ).copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _habitMeta(habit),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: SlowlightTypography.caption(
                                  context,
                                ).copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (showWeek) ...[
                          SizedBox(width: 154, child: _weekDots(habit, color)),
                          const SizedBox(width: 6),
                        ],
                        FxInkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => _toggleToday(habit),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: Container(
                                width: 26,
                                height: 26,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      habit.checkedToday
                                          ? color
                                          : Colors.transparent,
                                  border: Border.all(
                                    color:
                                        habit.checkedToday
                                            ? color
                                            : theme.colorScheme.outline,
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  LucideIcons.check,
                                  size: 14,
                                  color:
                                      habit.checkedToday
                                          ? Colors.white
                                          : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .05),
                  border: Border.all(color: color.withValues(alpha: .24)),
                  borderRadius: BorderRadius.circular(SlowlightRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _stats(habit),
                    const SizedBox(height: 12),
                    _heatmap(habit, color),
                    const SizedBox(height: 12),
                    Text(
                      '最近打卡',
                      style: SlowlightTypography.fieldLabel(context).copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 7),
                    _logs(habit, color),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FxButton(
                          label: '编辑',
                          icon: LucideIcons.pencil,
                          variant: FxButtonVariant.ghost,
                          size: FxButtonSize.sm,
                          onPressed: () => _editHabit(habit),
                        ),
                        FxMenu<String>(
                          tooltip: '更多',
                          onSelected: (value) {
                            if (value == 'backfill') _backfill(habit);
                            if (value == 'delete') _delete(habit);
                          },
                          itemBuilder:
                              (_) => const [
                                FxMenuItem(
                                  value: 'backfill',
                                  child: Text('补卡'),
                                ),
                                FxMenuItem(
                                  value: 'delete',
                                  child: Text('删除'),
                                ),
                              ],
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.ellipsis, size: 16),
                                SizedBox(width: 6),
                                Text('更多'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stats(Habit habit) {
    final logs = _controller.logsFor(habit.id);
    final now = DateTime.now();
    final monthPrefix = '${now.year}-${_two(now.month)}-';
    final monthCount =
        logs.where((log) => log.date.startsWith(monthPrefix)).length;
    final target =
        habit.frequency == 'daily'
            ? now.day
            : (habit.targetDays <= 0 ? monthCount : habit.targetDays * 4);
    final rate =
        target <= 0 ? 0 : (monthCount / target * 100).clamp(0, 100).round();
    final values = [
      ('${habit.streakCount}', '连续'),
      ('${habit.checkedDays.length}', '总计'),
      ('$rate%', '本月完成率'),
    ];
    return FxResponsiveFormGrid(
      minColumnWidth: 140,
      maxColumns: 3,
      horizontalGap: 8,
      verticalGap: 8,
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
    return Row(
      children: List.generate(7, (index) {
        final day = today.subtract(Duration(days: 6 - index));
        final key = '${day.year}-${_two(day.month)}-${_two(day.day)}';
        final active = checked.contains(key);
        return Expanded(
          child: Semantics(
            button: true,
            label: '${day.month}月${day.day}日${active ? '已打卡' : '未打卡'}',
            child: FxInkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _tapWeekDay(habit, day),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? color : Colors.transparent,
                      border: Border.all(
                        color:
                            active
                                ? color
                                : Theme.of(context).colorScheme.outline,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

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
    final time = '${_two(log.createdAt.hour)}:${_two(log.createdAt.minute)}';
    final parts = <String>[
      '${log.date.substring(5)} $time',
      if (log.durationMin > 0) '${log.durationMin} 分钟',
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
                    if (canCancel)
                      FxInkWell(
                        onTap: () => _toggleToday(habit),
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
    if (habit.specificTime.isNotEmpty) parts.add('目标 ${habit.specificTime}');
    if (habit.streakCount > 0) parts.add('连续 🔥 ${habit.streakCount} 天');
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
