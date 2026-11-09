import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/calendar_record.dart';
import '../models/todo_list.dart';
import '../repositories/calendar_repository.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/calendar_month_grid.dart';
import '../widgets/task_detail_sheet.dart';
import 'task_create_sheet.dart';

/// Calendar toolbar state shared by Android AppBar and desktop content.
class CalendarHeaderController extends ChangeNotifier {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  CalendarDisplayMode _mode = CalendarDisplayMode.all;
  bool _loading = false;
  Future<void> Function(int)? _onMoveMonth;
  Future<void> Function()? _onToday;
  void Function(CalendarDisplayMode)? _onFilter;

  DateTime get month => _month;
  CalendarDisplayMode get mode => _mode;
  bool get loading => _loading;

  void attach({
    required Future<void> Function(int) onMoveMonth,
    required Future<void> Function() onToday,
    required void Function(CalendarDisplayMode) onFilter,
  }) {
    _onMoveMonth = onMoveMonth;
    _onToday = onToday;
    _onFilter = onFilter;
  }

  void detach() {
    _onMoveMonth = null;
    _onToday = null;
    _onFilter = null;
  }

  void update(DateTime month, CalendarDisplayMode mode, bool loading) {
    if (_month.year == month.year && _month.month == month.month &&
        _mode == mode && _loading == loading) return;
    _month = month;
    _mode = mode;
    _loading = loading;
    notifyListeners();
  }

  Future<void> moveMonth(int delta) async {
    if (!_loading) await _onMoveMonth?.call(delta);
  }

  Future<void> goToday() async {
    if (!_loading) await _onToday?.call();
  }

  void setFilter(CalendarDisplayMode mode) => _onFilter?.call(mode);
}

/// FxMenu owns the anchored ShadPopover; the month picker does not open a
/// second dialog or duplicate the calendar's data-loading state.
class CalendarMonthTitle extends StatelessWidget {
  const CalendarMonthTitle({super.key, required this.controller});

  final CalendarHeaderController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => FxMenu<int>(
        tooltip: '切换年月',
        enabled: !controller.loading,
        constraints: const BoxConstraints(minWidth: 218, maxWidth: 240),
        contentBuilder: (context, dismiss) => Padding(
          padding: const EdgeInsets.all(10),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    FxIconButton(
                      icon: LucideIcons.chevronLeft,
                      tooltip: '上个月',
                      onPressed: () => controller.moveMonth(-1),
                    ),
                    Text(
                      '${controller.month.year} 年 ${controller.month.month} 月',
                      style: SlowlightTypography.secondary(context)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    FxIconButton(
                      icon: LucideIcons.chevronRight,
                      tooltip: '下个月',
                      onPressed: () => controller.moveMonth(1),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FxButton(
                  label: '回到今天',
                  variant: FxButtonVariant.outline,
                  size: FxButtonSize.sm,
                  onPressed: () async {
                    dismiss();
                    await controller.goToday();
                  },
                ),
              ],
            ),
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: SlowlightPlatformDensity.usesMobileTouchTargets ? 44 : 30,
            maxWidth: SlowlightPlatformDensity.usesMobileTouchTargets ? 190 : 260,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                '${controller.month.year} 年 ${controller.month.month} 月',
                key: const ValueKey('calendar-month-label'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SlowlightTypography.componentPageTitle(context),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(LucideIcons.chevronDown, size: 16),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

/// Filtering changes month cells only; the selected day shows all records.
class CalendarHeaderActions extends StatelessWidget {
  const CalendarHeaderActions({super.key, required this.controller});

  final CalendarHeaderController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FxIconButton(
          key: const ValueKey('calendar-today'),
          icon: LucideIcons.calendarDays,
          tooltip: '回到今天',
          onPressed: controller.loading ? null : controller.goToday,
        ),
        FxMenu<CalendarDisplayMode>(
          key: const ValueKey('calendar-filter'),
          tooltip: '月格筛选',
          initialValue: controller.mode,
          onSelected: controller.setFilter,
          constraints: const BoxConstraints(minWidth: 140, maxWidth: 180),
          itemBuilder: (context) => [
            for (final mode in CalendarDisplayMode.values)
              FxMenuItem<CalendarDisplayMode>(
                value: mode,
                height: SlowlightPlatformDensity.usesMobileTouchTargets ? 44 : 36,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(switch (mode) {
                      CalendarDisplayMode.all => '全部',
                      CalendarDisplayMode.plan => '计划',
                      CalendarDisplayMode.actual => '实际',
                    }),
                    if (controller.mode == mode)
                      const Icon(LucideIcons.check, size: 16),
                  ],
                ),
              ),
          ],
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: SlowlightPlatformDensity.usesMobileTouchTargets ? 44 : 32,
              minHeight: SlowlightPlatformDensity.iconButtonVisualSize,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.listFilter, size: 19),
                  if (controller.mode != CalendarDisplayMode.all) ...[
                    const SizedBox(width: 4),
                    Text(
                      controller.mode == CalendarDisplayMode.plan ? '计划' : '实际',
                      style: SlowlightTypography.caption(context),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class CalendarScreen extends StatefulWidget {
  final CalendarMonthLoader? monthLoader;
  final DateTime? initialMonth;
  final DateTime? initialSelectedDate;
  final CalendarHeaderController? headerController;
  /// True when the surrounding Android AppBar owns the header actions.
  final bool headerInAppBar;
  final int refreshTick;
  /// Allows deterministic editor-entry widget tests without remote list reads.
  final List<TodoList>? createListsOverride;
  final Future<void> Function(BuildContext context, DateTime date)?
  createTaskOverride;

  const CalendarScreen({
    super.key,
    this.monthLoader,
    this.initialMonth,
    this.initialSelectedDate,
    this.headerController,
    this.headerInAppBar = false,
    this.refreshTick = 0,
    this.createListsOverride,
    this.createTaskOverride,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _dayPanelKey = GlobalKey();
  late final CalendarHeaderController _headerController;
  late final bool _ownsHeaderController;
  late DateTime _focused;
  late DateTime _selected;
  late final CalendarMonthLoader _monthLoader;
  CalendarMonthData? _data;
  CalendarDisplayMode _displayMode = CalendarDisplayMode.all;
  bool _loading = true;
  bool _loadFailed = false;
  int _loadVersion = 0;

  bool get _hasCurrentMonth => _data != null &&
      _data!.month.year == _focused.year &&
      _data!.month.month == _focused.month;
  List<CalendarRecord> get _records =>
      _hasCurrentMonth ? _data!.records : const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final month = widget.initialMonth ?? now;
    _focused = DateTime(month.year, month.month, 1);
    final selected = widget.initialSelectedDate ?? now;
    _selected = DateTime(selected.year, selected.month, selected.day);
    _monthLoader = widget.monthLoader ?? CalendarRepository().loadMonth;
    _ownsHeaderController = widget.headerController == null;
    _headerController = widget.headerController ?? CalendarHeaderController();
    _headerController.attach(onMoveMonth: _moveMonth, onToday: _goToday,
        onFilter: _setFilter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifyHeader();
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick == widget.refreshTick) return;
    final revision = widget.refreshTick;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.refreshTick == revision) _load(keepCurrent: true);
    });
  }

  // An Android AppBar can already be listening while the CalendarScreen is
  // first mounted. Avoid notifying its AnimatedBuilder during build.
  void _notifyHeader() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _headerController.update(_focused, _displayMode, _loading);
    });
  }

  void _setFilter(CalendarDisplayMode mode) {
    setState(() => _displayMode = mode);
    _notifyHeader();
  }

  @override
  void dispose() {
    _headerController.detach();
    if (_ownsHeaderController) _headerController.dispose();
    super.dispose();
  }

  Future<void> _load({bool keepCurrent = false}) async {
    final requested = DateTime(_focused.year, _focused.month, 1);
    final version = ++_loadVersion;
    if (mounted) setState(() {
      // Revisiting a Tab must not blank an already confirmed month.
      _loading = !(keepCurrent && _hasCurrentMonth);
      _loadFailed = false;
    });
    _notifyHeader();
    try {
      final data = await _monthLoader(requested);
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _data = data;
        _loadFailed = false;
        _loading = false;
      });
      _notifyHeader();
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        // 保留上次成功的数据，仅在月份相符时继续展示。
        // 禁止把接口失败伪造成本月零条记录。
        _loadFailed = true;
        _loading = false;
      });
      _notifyHeader();
    }
  }

  Future<void> _moveMonth(int delta) async {
    if (_loading) return;
    final next = DateTime(_focused.year, _focused.month + delta, 1);
    setState(() {
      _focused = next;
      _selected = next;
    });
    _notifyHeader();
    await _load();
  }

  Future<void> _goToday() async {
    final today = DateTime.now();
    setState(() {
      _focused = DateTime(today.year, today.month, 1);
      _selected = DateTime(today.year, today.month, today.day);
    });
    _notifyHeader();
    await _load();
  }

  Future<void> _selectDate(DateTime date) async {
    final changeMonth =
        date.year != _focused.year || date.month != _focused.month;
    setState(() {
      _selected = DateTime(date.year, date.month, date.day);
      if (changeMonth) _focused = DateTime(date.year, date.month, 1);
    });
    if (changeMonth) {
      _notifyHeader();
      await _load();
    }
  }

  Future<void> _addTask(DateTime date) async {
    await _selectDate(date);
    if (!mounted) return;
    if (widget.createTaskOverride != null) {
      await widget.createTaskOverride!(context, date);
      await _load();
      return;
    }
    if (SlowlightPlatformDensity.usesMobileTouchTargets) {
      await TaskDetailSheet.showCreate(
        context,
        lists: widget.createListsOverride,
        initialDueDate: date,
        defaultDueToday: false,
        onChanged: _load,
      );
      return;
    }
    final created = await TaskCreateSheet.showFullCreate(
      context,
      defaultDueDate: date,
      defaultToToday: false,
    );
    if (created == true && mounted) await _load();
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
        padding: EdgeInsets.fromLTRB(20, widget.headerInAppBar ? 4 : 18, 20, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.headerInAppBar) ...[
                    _toolbar(),
                    const SizedBox(height: 12),
                  ],
                  if (_hasCurrentMonth && _data!.unavailableTypes.isNotEmpty)
                    _partialDataNotice(),
                  if (_loadFailed && _hasCurrentMonth)
                    _monthRefreshFailedNotice(),
                  if (_loading && !_hasCurrentMonth)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: FxCircularProgress()),
                    )
                  else if (_loadFailed && !_hasCurrentMonth)
                    FxEmptyState(
                      icon: LucideIcons.triangleAlert,
                      title: '当前月份读取失败',
                      subtitle: '未能加载这一个月的记录；请重试，不代表没有安排。',
                      action: FxButton(label: '重新加载', onPressed: _load),
                    )
                  else ...[
                  GestureDetector(
                    onHorizontalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity.abs() > 250) _moveMonth(velocity < 0 ? 1 : -1);
                    },
                    child: CalendarMonthGrid(
                    focusedMonth: _focused,
                    selectedDate: _selected,
                    records: _records,
                    displayMode: _displayMode,
                    // A same-month refresh must not blank confirmed cells.
                    loading: _loading && !_hasCurrentMonth,
                    onSelectDate: _selectDate,
                    onAddTask: _addTask,
                    onOpenRecord: _openRecord,
                    onShowMore: _showMore,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _dayPanel(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar() => Row(
    children: [
      CalendarMonthTitle(controller: _headerController),
      const Spacer(),
      CalendarHeaderActions(controller: _headerController),
    ],
  );

  Widget _monthRefreshFailedNotice() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: FxCard(
      padding: const EdgeInsets.all(12),
      expanded: true,
      child: Row(children: [
        const Icon(LucideIcons.triangleAlert, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(
          '刷新失败，当前仍展示上次读取的记录',
          style: SlowlightTypography.secondary(context),
        )),
        FxButton(
          label: '重试',
          size: FxButtonSize.sm,
          variant: FxButtonVariant.ghost,
          onPressed: _loading ? null : _load,
        ),
      ]),
    ),
  );

  Widget _partialDataNotice() {
    final labels = _data!.unavailableTypes.map(
      (type) => switch (type) {
        CalendarRecordType.task => '任务',
        CalendarRecordType.habit => '习惯',
        CalendarRecordType.focus => '专注',
        CalendarRecordType.reflection => '观察',
      },
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FxCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        expanded: true,
        child: Row(children: [
          const Icon(LucideIcons.triangleAlert, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(
            '${labels.join('、')}记录暂时不可用，其他数据仍可浏览。',
            style: SlowlightTypography.caption(context),
          )),
          const SizedBox(width: 8),
          FxButton(
            key: const ValueKey('calendar-partial-retry'),
            label: '重试',
            size: FxButtonSize.sm,
            variant: FxButtonVariant.ghost,
            onPressed: _loading ? null : _load,
          ),
        ]),
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
    final contextInfo = Wrap(
      spacing: 10,
      runSpacing: 8,
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
              _hasCurrentMonth && _data!.unavailableTypes.isNotEmpty
                  ? '计划与实际 · 已载入 ${records.length} 条记录（部分待核对）'
                  : '计划与实际 · 共 ${records.length} 条完整记录',
              style: SlowlightTypography.caption(context).copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        _summary(records),
      ],
    );
    return FxCard(
      key: _dayPanelKey,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FxActionBar(
            leading: contextInfo,
            actions: [
              FxButton(
                key: const ValueKey('calendar-add-task'),
                label: '新建任务',
                icon: LucideIcons.plus,
                size: FxButtonSize.sm,
                onPressed: () => _addTask(_selected),
              ),
            ],
            stackBelow: 680,
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
              _hasCurrentMonth && _data!.unavailableTypes.isNotEmpty
                  ? '部分数据源未读取成功，请重试后核对当天记录。'
                  : taskSection
                      ? '当天没有任务计划。'
                      : '当天还没有习惯、专注或观察记录。',
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
      if (record.amountLabel.isNotEmpty) record.amountLabel,
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
              record.kind == CalendarRecordKind.plan ? '计划 ›' : '已记录 ›',
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
    // Clicking a month chip must also drive the selected-day detail,
    // matching the prototype; opening a dialog alone left a stale day panel.
    await _selectDate(record.date);
    if (!mounted) return;
    if (record.task != null) {
      // The canonical editor already loads and validates real lists with
      // failure feedback; a second pre-read here could throw uncaught.
      await TaskDetailSheet.show(
        context,
        task: record.task!,
        lists: const <TodoList>[],
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
                if (record.amountLabel.isNotEmpty)
                  _detailLine('数量', record.amountLabel),
                if (record.dimensionLabel.isNotEmpty)
                  _detailLine('历史分类', record.dimensionLabel),
                const SizedBox(height: 12),
                FxDialogActions(
                  actions: [
                    FxButton(
                      label: '关闭',
                      variant: FxButtonVariant.outline,
                      onPressed:
                          () =>
                              Navigator.of(
                                dialogContext,
                                rootNavigator: true,
                              ).pop(),
                    ),
                  ],
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

  // 与月格筛选独立：当日事实始终完整，见 CalendarScreen 的页面测试。
  List<CalendarRecord> _recordsForDay(DateTime date) => _records
      .where((record) => _sameDay(record.date, date))
      .toList(growable: false);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
