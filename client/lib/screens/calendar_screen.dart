import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/calendar_record.dart';
import '../repositories/calendar_repository.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/calendar_month_grid.dart';
import '../widgets/task_detail_sheet.dart';
import 'task_create_sheet.dart';

class CalendarScreen extends StatefulWidget {
  final CalendarMonthLoader? monthLoader;
  final DateTime? initialMonth;
  final DateTime? initialSelectedDate;
  final Future<void> Function(BuildContext context, DateTime date)?
  createTaskOverride;

  const CalendarScreen({
    super.key,
    this.monthLoader,
    this.initialMonth,
    this.initialSelectedDate,
    this.createTaskOverride,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _dayPanelKey = GlobalKey();
  late DateTime _focused;
  late DateTime _selected;
  late final CalendarMonthLoader _monthLoader;
  CalendarMonthData? _data;
  CalendarDisplayMode _displayMode = CalendarDisplayMode.all;
  bool _loading = true;

  List<CalendarRecord> get _records => _data?.records ?? const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final month = widget.initialMonth ?? now;
    _focused = DateTime(month.year, month.month, 1);
    final selected = widget.initialSelectedDate ?? now;
    _selected = DateTime(selected.year, selected.month, selected.day);
    _monthLoader = widget.monthLoader ?? CalendarRepository().loadMonth;
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = await _monthLoader(_focused);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _data = CalendarMonthData(month: _focused, records: const []);
        _loading = false;
      });
    }
  }

  Future<void> _moveMonth(int delta) async {
    if (_loading) return;
    final next = DateTime(_focused.year, _focused.month + delta, 1);
    setState(() {
      _focused = next;
      _selected = next;
    });
    await _load();
  }

  Future<void> _goToday() async {
    final today = DateTime.now();
    setState(() {
      _focused = DateTime(today.year, today.month, 1);
      _selected = DateTime(today.year, today.month, today.day);
    });
    await _load();
  }

  Future<void> _selectDate(DateTime date) async {
    final changeMonth =
        date.year != _focused.year || date.month != _focused.month;
    setState(() {
      _selected = DateTime(date.year, date.month, date.day);
      if (changeMonth) _focused = DateTime(date.year, date.month, 1);
    });
    if (changeMonth) await _load();
  }

  Future<void> _addTask(DateTime date) async {
    await _selectDate(date);
    if (!mounted) return;
    if (widget.createTaskOverride != null) {
      await widget.createTaskOverride!(context, date);
      await _load();
      return;
    }
    final created = await TaskCreateSheet.showFullCreate(
      context,
      defaultDueDate: date,
      defaultToToday: false,
    );
    if (created == true) await _load();
  }

  void _showMore(DateTime date) {
    _selectDate(date);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final panelContext = _dayPanelKey.currentContext;
      if (panelContext != null) {
        Scrollable.ensureVisible(
          panelContext,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: .12,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FxRefresh(
      onRefresh: _load,
      child: ListView(
        key: const ValueKey('calendar-scroll-view'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _toolbar(),
                  const SizedBox(height: 12),
                  if ((_data?.unavailableTypes.isNotEmpty ?? false))
                    _partialDataNotice(),
                  CalendarMonthGrid(
                    focusedMonth: _focused,
                    selectedDate: _selected,
                    records: _records,
                    displayMode: _displayMode,
                    loading: _loading,
                    onSelectDate: _selectDate,
                    onAddTask: _addTask,
                    onOpenRecord: _openRecord,
                    onShowMore: _showMore,
                  ),
                  const SizedBox(height: 14),
                  _dayPanel(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 8,
      children: [
        FxButton(
          key: const ValueKey('calendar-today'),
          label: '今天',
          size: FxButtonSize.sm,
          variant: FxButtonVariant.outline,
          onPressed: _loading ? null : _goToday,
        ),
        _monthButton(LucideIcons.chevronLeft, '上个月', () => _moveMonth(-1)),
        _monthButton(LucideIcons.chevronRight, '下个月', () => _moveMonth(1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Text(
            '${_focused.year} 年 ${_focused.month} 月',
            key: const ValueKey('calendar-month-label'),
            style: SlowlightTypography.cardTitle(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (!compact) _filter(),
      ],
    );
  }

  Widget _monthButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return FxIconButton(
      icon: icon,
      iconSize: 17,
      tooltip: tooltip,
      variant: FxIconButtonVariant.outline,
      onPressed: _loading ? null : onPressed,
    );
  }

  Widget _filter() {
    return FxSegmented(
      labels: const ['全部', '计划', '实际'],
      selectedIndex: _displayMode.index,
      onChanged:
          (index) =>
              setState(() => _displayMode = CalendarDisplayMode.values[index]),
    );
  }

  Widget _partialDataNotice() {
    final labels = _data!.unavailableTypes.map(
      (type) => switch (type) {
        CalendarRecordType.task => '任务',
        CalendarRecordType.habit => '习惯',
        CalendarRecordType.focus => '专注',
        CalendarRecordType.reflection => '观察',
      },
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Text(
        '${labels.join('、')}记录暂时不可用，其他数据仍可浏览。',
        style: SlowlightTypography.caption(context),
      ),
    );
  }

  Widget _dayPanel() {
    final records = _recordsForDay(_selected);
    final tasks = records
        .where((record) => record.type == CalendarRecordType.task)
        .toList(growable: false);
    final activities = records
        .where((record) => record.type != CalendarRecordType.task)
        .toList(growable: false);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return FxCard(
      key: _dayPanelKey,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_selected.month} 月 ${_selected.day} 日 · 周${weekdays[_selected.weekday - 1]}',
                    key: const ValueKey('calendar-selected-title'),
                    style: SlowlightTypography.secondary(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '计划与实际 · 共 ${records.length} 条完整记录',
                    style: SlowlightTypography.caption(context).copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              _summary(records),
              FxButton(
                key: const ValueKey('calendar-add-task'),
                label: '新建任务',
                icon: LucideIcons.plus,
                size: FxButtonSize.sm,
                onPressed: () => _addTask(_selected),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final taskSection = _recordSection('当日任务', tasks, true);
              final activitySection = _recordSection('当日足迹', activities, false);
              if (!wide) {
                return Column(
                  children: [
                    taskSection,
                    const SizedBox(height: 16),
                    activitySection,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: taskSection),
                  const SizedBox(width: 22),
                  Expanded(flex: 4, child: activitySection),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _summary(List<CalendarRecord> records) {
    final tasks = records.where((r) => r.type == CalendarRecordType.task);
    final completed = tasks.where((r) => r.completed).length;
    final habits =
        records.where((r) => r.type == CalendarRecordType.habit).length;
    final focus = records
        .where((r) => r.type == CalendarRecordType.focus)
        .fold<int>(0, (sum, r) => sum + r.durationMin);
    final observations =
        records.where((r) => r.type == CalendarRecordType.reflection).length;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _summaryChip('任务 $completed/${tasks.length}'),
        _summaryChip('习惯 $habits'),
        _summaryChip('专注 ${focus}min'),
        _summaryChip('观察 $observations'),
      ],
    );
  }

  Widget _summaryChip(String text) =>
      FxChip(label: text, variant: FxChipVariant.secondary);

  Widget _recordSection(
    String title,
    List<CalendarRecord> records,
    bool taskSection,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: SlowlightTypography.caption(context).copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (records.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              taskSection ? '当天没有任务计划。' : '当天还没有习惯、专注或观察记录。',
              style: SlowlightTypography.secondary(
                context,
              ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          )
        else
          ...records.map(_recordRow),
      ],
    );
  }

  Widget _recordRow(CalendarRecord record) {
    final theme = Theme.of(context);
    final meta = <String>[
      if (record.timeLabel.isNotEmpty) record.timeLabel,
      if (record.dimensionLabel.isNotEmpty) record.dimensionLabel,
      if (record.durationMin > 0) '${record.durationMin}min',
    ].join(' · ');
    final scaledSecondary = MediaQuery.textScalerOf(
      context,
    ).scale(SlowlightTypography.secondarySize);
    final titleMaxLines =
        scaledSecondary >= SlowlightTypography.secondarySize * 1.3 ? 2 : 1;
    return FxInkWell(
      key: ValueKey('calendar-record-${record.id}'),
      onTap: () => _openRecord(record),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: calendarRecordColor(record, context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
                    maxLines: titleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: SlowlightTypography.secondary(
                      context,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      style: SlowlightTypography.caption(
                        context,
                      ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              record.completed ? '已记录 ›' : '待完成 ›',
              style: SlowlightTypography.caption(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRecord(CalendarRecord record) async {
    if (record.task != null) {
      final lists = await DataService().getLists();
      if (!mounted) return;
      await TaskDetailSheet.show(
        context,
        task: record.task!,
        lists: lists,
        onChanged: _load,
      );
      return;
    }
    if (!mounted) return;
    await FxDialog.show<void>(
      context: context,
      title: record.title,
      child: Builder(
        builder:
            (dialogContext) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: calendarRecordColor(record, dialogContext),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${record.typeLabel} · ${record.kindLabel}'),
                  ],
                ),
                const SizedBox(height: 12),
                if (record.description.isNotEmpty) ...[
                  Text(record.description),
                  const SizedBox(height: 14),
                ],
                _detailLine('状态', record.completed ? '已记录' : '待完成'),
                if (record.timeLabel.isNotEmpty)
                  _detailLine('时间', record.timeLabel),
                if (record.durationMin > 0)
                  _detailLine('时长', '${record.durationMin} 分钟'),
                if (record.dimensionLabel.isNotEmpty)
                  _detailLine('观察维度', record.dimensionLabel),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FxButton(
                    label: '关闭',
                    variant: FxButtonVariant.outline,
                    onPressed:
                        () =>
                            Navigator.of(
                              dialogContext,
                              rootNavigator: true,
                            ).pop(),
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _detailLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: SlowlightTypography.secondary(
              context,
            ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: SlowlightTypography.secondary(
              context,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  List<CalendarRecord> _recordsForDay(DateTime date) => _records
      .where((record) => _sameDay(record.date, date))
      .toList(growable: false);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
