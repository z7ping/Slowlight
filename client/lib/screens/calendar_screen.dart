import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/calendar_record.dart';
import '../models/todo_list.dart';
import '../repositories/calendar_repository.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/calendar_month_grid.dart';
import '../widgets/task_detail_sheet.dart';
import 'task_create_sheet.dart';

enum CalendarViewMode { month, day, threeDays, week }

/// Calendar toolbar state shared by Android AppBar and desktop content.
class CalendarHeaderController extends ChangeNotifier {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  CalendarDisplayMode _mode = CalendarDisplayMode.all;
  CalendarViewMode _viewMode = CalendarViewMode.month;
  bool _loading = false;
  Future<void> Function(int)? _onMoveMonth;
  Future<void> Function()? _onToday;
  void Function(CalendarDisplayMode)? _onFilter;
  void Function(CalendarViewMode)? _onViewMode;

  DateTime get month => _month;
  CalendarDisplayMode get mode => _mode;
  CalendarViewMode get viewMode => _viewMode;
  bool get loading => _loading;

  void attach({
    required Future<void> Function(int) onMoveMonth,
    required Future<void> Function() onToday,
    required void Function(CalendarDisplayMode) onFilter,
    required void Function(CalendarViewMode) onViewMode,
  }) {
    _onMoveMonth = onMoveMonth;
    _onToday = onToday;
    _onFilter = onFilter;
    _onViewMode = onViewMode;
  }

  void detach() {
    _onMoveMonth = null;
    _onToday = null;
    _onFilter = null;
    _onViewMode = null;
  }

  void update(DateTime month, CalendarDisplayMode mode,
      CalendarViewMode viewMode, bool loading) {
    if (_month.year == month.year && _month.month == month.month &&
        _mode == mode && _viewMode == viewMode && _loading == loading) return;
    _month = month;
    _mode = mode;
    _viewMode = viewMode;
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
  void setViewMode(CalendarViewMode mode) => _onViewMode?.call(mode);
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
        FxMenu<CalendarViewMode>(
          key: const ValueKey('calendar-view-toggle'),
          tooltip: '切换日历视图',
          onSelected: controller.setViewMode,
          initialValue: controller.viewMode,
          constraints: const BoxConstraints(minWidth: 174, maxWidth: 220),
          itemBuilder: (context) => [
            for (final view in CalendarViewMode.values)
              FxMenuItem<CalendarViewMode>(
                value: view,
                height: SlowlightPlatformDensity.usesMobileTouchTargets ? 44 : 36,
                child: Row(
                  children: [
                    Icon(switch (view) {
                      CalendarViewMode.month => LucideIcons.calendarDays,
                      CalendarViewMode.day => LucideIcons.list,
                      CalendarViewMode.threeDays => LucideIcons.columns3,
                      CalendarViewMode.week => LucideIcons.calendarRange,
                    }, size: 17),
                    const SizedBox(width: 10),
                    Expanded(child: Text(switch (view) {
                      CalendarViewMode.month => '月历',
                      CalendarViewMode.day => '单日 Timeline',
                      CalendarViewMode.threeDays => '三日视图',
                      CalendarViewMode.week => '七日视图',
                    })),
                    if (controller.viewMode == view)
                      const Icon(LucideIcons.check, size: 16),
                  ],
                ),
              ),
          ],
          child: SizedBox(
            width: SlowlightPlatformDensity.usesMobileTouchTargets ? 44 : 34,
            height: SlowlightPlatformDensity.iconButtonVisualSize,
            child: Center(
              child: Icon(switch (controller.viewMode) {
                CalendarViewMode.month => LucideIcons.calendarDays,
                CalendarViewMode.day => LucideIcons.list,
                CalendarViewMode.threeDays => LucideIcons.columns3,
                CalendarViewMode.week => LucideIcons.calendarRange,
              }, size: 19),
            ),
          ),
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
  CalendarViewMode _viewMode = CalendarViewMode.month;
  bool _modeTouched = false;
  final Map<int, CalendarMonthData> _rangeCache = {};
  bool _rangeLoading = false;
  bool _rangeFailed = false;
  int _rangeVersion = 0;

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
        onFilter: _setFilter, onViewMode: _setViewMode);
    _restoreViewMode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifyHeader();
    });
    _load();
  }

  // An Android AppBar can already be listening while the CalendarScreen is
  // first mounted. Avoid notifying its AnimatedBuilder during build.
  void _notifyHeader() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _headerController.update(
          _focused, _displayMode, _viewMode, _loading);
    });
  }

  void _setFilter(CalendarDisplayMode mode) {
    setState(() => _displayMode = mode);
    _notifyHeader();
  }

  static const _viewPreferenceKey = 'calendar.view_mode';

  Future<void> _restoreViewMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_viewPreferenceKey);
      if (!mounted || _modeTouched) return;
      final restored = CalendarViewMode.values.where((v) => v.name == name);
      if (restored.isNotEmpty) _setViewMode(restored.first, persist: false);
    } catch (_) {
      // A preference failure must not block the calendar.
    }
  }

  void _setViewMode(CalendarViewMode view, {bool persist = true}) {
    if (persist) _modeTouched = true;
    if (_viewMode == view) return;
    setState(() => _viewMode = view);
    _notifyHeader();
    if (persist) {
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setString(_viewPreferenceKey, view.name))
          .catchError((Object _) => false);
    }
    _rangeVersion++;
    if (_hasCurrentMonth && view != CalendarViewMode.month) {
      _ensureRange();
    } else if (_rangeLoading || _rangeFailed) {
      setState(() { _rangeLoading = false; _rangeFailed = false; });
    }
  }

  @override
  void dispose() {
    _rangeVersion++;
    _headerController.detach();
    if (_ownsHeaderController) _headerController.dispose();
    super.dispose();
  }

  int _monthKey(DateTime date) => date.year * 12 + date.month;

  List<DateTime> _visibleDays() {
    if (_viewMode == CalendarViewMode.month) return const [];
    final anchor = DateTime(_selected.year, _selected.month, _selected.day);
    final count = switch (_viewMode) {
      CalendarViewMode.day => 1,
      CalendarViewMode.threeDays => 3,
      CalendarViewMode.week => 7,
      CalendarViewMode.month => 0,
    };
    final start = _viewMode == CalendarViewMode.week
        ? DateTime(anchor.year, anchor.month, anchor.day - anchor.weekday + 1)
        : anchor;
    return List.generate(count,
        (index) => DateTime(start.year, start.month, start.day + index));
  }

  /// The existing month loader is reused for cross-month day columns.
  /// Missing adjacent months show a retry state, never a false empty day.
  Future<void> _ensureRange() async {
    if (!mounted || !_hasCurrentMonth ||
        _viewMode == CalendarViewMode.month) return;
    final months = <int, DateTime>{};
    for (final day in _visibleDays()) {
      final key = _monthKey(day);
      if (key != _monthKey(_focused) && !_rangeCache.containsKey(key)) {
        months[key] = DateTime(day.year, day.month, 1);
      }
    }
    if (months.isEmpty) {
      if (_rangeLoading || _rangeFailed) {
        setState(() {
          _rangeLoading = false;
          _rangeFailed = false;
        });
      }
      return;
    }
    final version = ++_rangeVersion;
    setState(() {
      _rangeLoading = true;
      _rangeFailed = false;
    });
    try {
      final results = await Future.wait(months.values.map(_monthLoader));
      if (!mounted || version != _rangeVersion) return;
      setState(() {
        for (final data in results) {
          _rangeCache[_monthKey(data.month)] = data;
        }
        _rangeLoading = false;
      });
    } catch (_) {
      if (!mounted || version != _rangeVersion) return;
      setState(() {
        _rangeLoading = false;
        _rangeFailed = true;
      });
    }
  }

  Future<void> _retryRange() async {
    _rangeCache.removeWhere((key, _) => key != _monthKey(_focused));
    await _ensureRange();
  }

  Future<void> _shiftPeriod(int direction) async {
    if (_loading || _rangeLoading) return;
    final step = switch (_viewMode) {
      CalendarViewMode.day => 1,
      CalendarViewMode.threeDays => 3,
      CalendarViewMode.week => 7,
      CalendarViewMode.month => 1,
    };
    final next = DateTime(_selected.year, _selected.month,
        _selected.day + step * direction);
    await _selectDate(next);
    if (mounted && _viewMode != CalendarViewMode.month) {
      await _ensureRange();
    }
  }

  Future<void> _load() async {
    final requested = DateTime(_focused.year, _focused.month, 1);
    final version = ++_loadVersion;
    if (mounted) setState(() {
      _loading = true;
      _loadFailed = false;
    });
    _notifyHeader();
    try {
      final data = await _monthLoader(requested);
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _data = data;
        _rangeCache[_monthKey(requested)] = data;
        _loadFailed = false;
        _loading = false;
      });
      _notifyHeader();
      await _ensureRange();
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
    } else if (_viewMode != CalendarViewMode.month) {
      await _ensureRange();
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
                    if (_viewMode == CalendarViewMode.month) ...[
                      GestureDetector(
                        onHorizontalDragEnd: (details) {
                          final velocity = details.primaryVelocity ?? 0;
                          if (velocity.abs() > 250) {
                            _moveMonth(velocity < 0 ? 1 : -1);
                          }
                        },
                        child: CalendarMonthGrid(
                          focusedMonth: _focused,
                          selectedDate: _selected,
                          records: _records,
                          displayMode: _displayMode,
                          loading: _loading && !_hasCurrentMonth,
                          onSelectDate: _selectDate,
                          onAddTask: _addTask,
                          onOpenRecord: _openRecord,
                          onShowMore: _showMore,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _dayPanel(),
                    ] else ...[
                      _periodNavigation(),
                      const SizedBox(height: 10),
                      if (_rangeLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 36),
                          child: Center(child: FxCircularProgress()),
                        )
                      else if (_rangeFailed)
                        FxEmptyState(
                          icon: LucideIcons.triangleAlert,
                          title: '部分日期读取失败',
                          subtitle: '跨月记录尚未核实，不能按无记录展示。',
                          action: FxButton(
                            label: '重新加载',
                            onPressed: _retryRange,
                          ),
                        )
                      else
                        _timelineBoard(),
                      if (_viewMode != CalendarViewMode.day &&
                          !_rangeLoading && !_rangeFailed) ...[
                        const SizedBox(height: 14),
                        _dayPanel(),
                      ],
                    ],
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

  Widget _periodNavigation() {
    final days = _visibleDays();
    if (days.isEmpty) return const SizedBox.shrink();
    final start = days.first, end = days.last;
    final period = days.length == 1
        ? '${start.month} 月 ${start.day} 日'
        : '${start.month}/${start.day} – ${end.month}/${end.day}';
    return Row(
      children: [
        FxIconButton(
          key: const ValueKey('calendar-period-prev'),
          icon: LucideIcons.chevronLeft,
          tooltip: '上一时段',
          onPressed: _loading || _rangeLoading ? null : () => _shiftPeriod(-1),
        ),
        Expanded(
          child: Text(period,
              textAlign: TextAlign.center,
              style: SlowlightTypography.secondary(context)
                  .copyWith(fontWeight: FontWeight.w700)),
        ),
        FxIconButton(
          key: const ValueKey('calendar-period-next'),
          icon: LucideIcons.chevronRight,
          tooltip: '下一时段',
          onPressed: _loading || _rangeLoading ? null : () => _shiftPeriod(1),
        ),
        FxIconButton(
          key: const ValueKey('calendar-period-add-task'),
          icon: LucideIcons.plus,
          tooltip: '在选中日期新建任务',
          onPressed: () => _addTask(_selected),
        ),
      ],
    );
  }

  List<CalendarRecord> _timelineRecords(DateTime day) {
    final source = _rangeCache[_monthKey(day)];
    if (source == null) return const [];
    final result = source.records.where((record) {
      if (!_sameDay(record.date, day)) return false;
      return switch (_displayMode) {
        CalendarDisplayMode.all => true,
        CalendarDisplayMode.plan => record.kind == CalendarRecordKind.plan,
        CalendarDisplayMode.actual => record.kind == CalendarRecordKind.actual,
      };
    }).toList(growable: false);
    // Only native HH:mm values are clock times. Aggregate or periodic
    // labels are not fabricated into a scheduled hour.
    int minutes(CalendarRecord record) {
      final match = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$')
          .firstMatch(record.timeLabel);
      return match == null
          ? 1440
          : int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
    }
    result.sort((a, b) {
      final clock = minutes(a).compareTo(minutes(b));
      if (clock != 0) return clock;
      return a.kind.index.compareTo(b.kind.index);
    });
    return result;
  }

  Widget _timelineBoard() {
    final days = _visibleDays();
    final isLargeText = MediaQuery.textScalerOf(context)
            .scale(SlowlightTypography.secondarySize) >=
        SlowlightTypography.secondarySize * 1.3;
    return LayoutBuilder(
      builder: (context, constraints) {
        final minimum = days.length == 1
            ? constraints.maxWidth
            : days.length * (isLargeText ? 250.0 : 216.0);
        final boardWidth = constraints.maxWidth > minimum
            ? constraints.maxWidth
            : minimum;
        return SingleChildScrollView(
          key: const ValueKey('calendar-period-horizontal-scroll'),
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: boardWidth,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final day in days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _timelineDay(day),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _timelineDay(DateTime day) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final rows = _timelineRecords(day);
    final partial = _rangeCache[_monthKey(day)]!.unavailableTypes.isNotEmpty;
    final selected = _sameDay(day, _selected);
    final palette = Theme.of(context).colorScheme;
    return FxCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FxInkWell(
            key: ValueKey('calendar-period-day-${day.year}-${day.month}-${day.day}'),
            onTap: () => _selectDate(day),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected
                        ? activePalette.accent
                        : palette.outlineVariant,
                    width: selected ? 2 : 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Text('${day.month} 月 ${day.day} 日 · 周${weekdays[day.weekday-1]}',
                    style: SlowlightTypography.secondary(context)
                        .copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(partial ? '部分记录待核对' : '${rows.length} 条',
                    style: SlowlightTypography.caption(context)
                        .copyWith(color: palette.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                partial ? '部分来源未读取，请重试核对。' : '这天没有记录',
                textAlign: TextAlign.center,
                style: SlowlightTypography.caption(context)
                    .copyWith(color: palette.onSurfaceVariant),
              ),
            )
          else
            for (final record in rows) _timelineRecord(record),
        ],
      ),
    );
  }

  Widget _timelineRecord(CalendarRecord record) {
    final palette = Theme.of(context).colorScheme;
    final time = RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$')
            .hasMatch(record.timeLabel)
        ? record.timeLabel
        : '—';
    return FxInkWell(
      key: ValueKey('calendar-timeline-record-${record.id}'),
      onTap: () => _openRecord(record),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 43,
              child: Text(time,
                  maxLines: 1,
                  style: SlowlightTypography.caption(context)
                      .copyWith(color: palette.onSurfaceVariant)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(left: 9),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(
                    color: calendarRecordColor(record, context),
                    width: 2,
                  )),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: SlowlightTypography.secondary(context)
                          .copyWith(fontWeight: FontWeight.w600)),
                    Text([
                      record.kindLabel,
                      if (time == '—' && record.timeLabel.isNotEmpty)
                        record.timeLabel,
                      if (record.durationMin > 0)
                        '${record.durationMin}min',
                      if (record.amountLabel.isNotEmpty) record.amountLabel,
                    ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SlowlightTypography.caption(context)
                          .copyWith(color: palette.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
