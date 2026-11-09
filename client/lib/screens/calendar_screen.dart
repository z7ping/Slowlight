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
  Future<void> Function(int)? _onMovePeriod;
  Future<void> Function()? _onToday;
  void Function(CalendarDisplayMode)? _onFilter;
  void Function(CalendarViewMode)? _onViewMode;

  DateTime get month => _month;
  CalendarDisplayMode get mode => _mode;
  CalendarViewMode get viewMode => _viewMode;
  bool get loading => _loading;

  void attach({
    required Future<void> Function(int) onMoveMonth,
    required Future<void> Function(int) onMovePeriod,
    required Future<void> Function() onToday,
    required void Function(CalendarDisplayMode) onFilter,
    required void Function(CalendarViewMode) onViewMode,
  }) {
    _onMoveMonth = onMoveMonth;
    _onMovePeriod = onMovePeriod;
    _onToday = onToday;
    _onFilter = onFilter;
    _onViewMode = onViewMode;
  }

  void detach() {
    _onMoveMonth = null;
    _onMovePeriod = null;
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

  Future<void> movePeriod(int delta) async {
    if (!_loading) await _onMovePeriod?.call(delta);
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
    final mobile = SlowlightPlatformDensity.usesMobileTouchTargets;
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
            minHeight: mobile ? 44 : 30,
            maxWidth: mobile ? 112 : 260,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                mobile
                    ? '${controller.month.year}年${controller.month.month}月'
                    : '${controller.month.year} 年 ${controller.month.month} 月',
                key: const ValueKey('calendar-month-label'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mobile
                    ? SlowlightTypography.secondary(context)
                        .copyWith(fontWeight: FontWeight.w700)
                    : SlowlightTypography.componentPageTitle(context),
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
          key: const ValueKey('calendar-period-prev'),
          icon: LucideIcons.chevronLeft,
          iconSize: 16,
          tooltip: '上一周期',
          onPressed: controller.loading ? null : () => controller.movePeriod(-1),
        ),
        FxIconButton(
          key: const ValueKey('calendar-period-next'),
          icon: LucideIcons.chevronRight,
          iconSize: 16,
          tooltip: '下一周期',
          onPressed: controller.loading ? null : () => controller.movePeriod(1),
        ),
        if (SlowlightPlatformDensity.usesMobileTouchTargets &&
            MediaQuery.sizeOf(context).width >= 412)
          FxButton(
            label: '今天',
            size: FxButtonSize.sm,
            variant: FxButtonVariant.ghost,
            onPressed: controller.loading ? null : controller.goToday,
          ),
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
                      CalendarViewMode.month => '月',
                      CalendarViewMode.day => '日',
                      CalendarViewMode.threeDays => '三日',
                      CalendarViewMode.week => '七日',
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
                  if (controller.mode != CalendarDisplayMode.all &&
                       (!SlowlightPlatformDensity.usesMobileTouchTargets ||
                        MediaQuery.sizeOf(context).width >= 480)) ...[
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

class _CalendarDateHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  const _CalendarDateHeaderDelegate({required this.child, required this.height});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      child;
  @override
  bool shouldRebuild(covariant _CalendarDateHeaderDelegate oldDelegate) => true;
}

class CalendarScreen extends StatefulWidget {
  final CalendarMonthLoader? monthLoader;
  final DateTime? initialMonth;
  final DateTime? initialSelectedDate;
  final CalendarHeaderController? headerController;
  /// True when the surrounding Android AppBar owns the header actions.
  final bool headerInAppBar;
  /// Main shell refreshes this when revisiting the Calendar tab.
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
  static const _calendarAxisWidth = 36.0;
  static const _calendarHourHeight = 54.0;
  static const _calendarStartMinute = 8 * 60;
  static const _calendarEndMinute = 22 * 60;
  late final CalendarHeaderController _headerController;
  late final bool _ownsHeaderController;
  late DateTime _focused;
  late DateTime _selected;
  late DateTime _threeDayStart;
  late final CalendarMonthLoader _monthLoader;
  CalendarMonthData? _data;
  CalendarDisplayMode _displayMode = CalendarDisplayMode.all;
  bool _loading = true;
  bool _loadFailed = false;
  int _loadVersion = 0;
  CalendarViewMode _viewMode = CalendarViewMode.month;
  bool _modeTouched = false;
  bool _untimedExpanded = false;
  bool _otherTimeExpanded = false;
  String? _draggingRecordId;
  Offset _dragOrigin = Offset.zero;
  Offset _dragOffset = Offset.zero;
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
    _threeDayStart = _selected;
    _monthLoader = widget.monthLoader ?? CalendarRepository().loadMonth;
    _ownsHeaderController = widget.headerController == null;
    _headerController = widget.headerController ?? CalendarHeaderController();
    _viewMode = _headerController.viewMode;
    _headerController.attach(onMoveMonth: _moveMonth,
        onMovePeriod: _shiftPeriod, onToday: _goToday,
        onFilter: _setFilter, onViewMode: _setViewMode);
    _restoreViewMode();
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
      if (mounted && widget.refreshTick == revision) {
        _refresh(keepCurrent: true);
      }
    });
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
    if (persist) {
      _modeTouched = true;
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setString(_viewPreferenceKey, view.name))
          .catchError((Object _) => false);
    }
    if (_viewMode == view) return;
    setState(() {
      if (view == CalendarViewMode.threeDays) _threeDayStart = _selected;
      _untimedExpanded = false;
      _otherTimeExpanded = false;
      _viewMode = view;
    });
    _notifyHeader();
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
    final start = switch (_viewMode) {
      CalendarViewMode.week => DateTime(
          anchor.year, anchor.month, anchor.day - anchor.weekday + 1),
      CalendarViewMode.threeDays => _threeDayStart,
      _ => anchor,
    };
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
    if (_viewMode == CalendarViewMode.month) {
      await _moveMonth(direction);
      return;
    }
    final step = switch (_viewMode) {
      CalendarViewMode.day => 1,
      CalendarViewMode.threeDays => 3,
      CalendarViewMode.week => 7,
      CalendarViewMode.month => 1,
    };
    final anchor = _viewMode == CalendarViewMode.threeDays
        ? _threeDayStart : _selected;
    final next = DateTime(anchor.year, anchor.month,
        anchor.day + step * direction);
    if (_viewMode == CalendarViewMode.threeDays) _threeDayStart = next;
    if (mounted) setState(() {
      _untimedExpanded = false;
      _otherTimeExpanded = false;
    });
    await _selectDate(next);
  }

  Future<void> _refresh({bool keepCurrent = false}) async {
    _rangeVersion++;
    if (_viewMode != CalendarViewMode.month && mounted) {
      setState(() => _rangeLoading = true);
    }
    _rangeCache.clear();
    // Preserve confirmed same-month data during refresh, but do not label an
    // uncached neighbor as empty while the new request is pending.
    if (_hasCurrentMonth) _rangeCache[_monthKey(_focused)] = _data!;
    await _load(keepCurrent: keepCurrent);
  }

  Future<void> _load({bool keepCurrent = false}) async {
    final requested = DateTime(_focused.year, _focused.month, 1);
    final version = ++_loadVersion;
    if (mounted) setState(() {
      // Revisiting a tab retains confirmed cells until the next read settles.
      _loading = !(keepCurrent && _hasCurrentMonth);
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
        _rangeLoading = false;
        if (_viewMode != CalendarViewMode.month) _rangeFailed = true;
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
      if (_viewMode == CalendarViewMode.threeDays) _threeDayStart = next;
    });
    _notifyHeader();
    await _load();
  }

  Future<void> _goToday() async {
    final today = DateTime.now();
    setState(() {
      _focused = DateTime(today.year, today.month, 1);
      _selected = DateTime(today.year, today.month, today.day);
      if (_viewMode == CalendarViewMode.threeDays) _threeDayStart = _selected;
    });
    _notifyHeader();
    await _load();
  }

  Future<void> _selectDate(DateTime date) async {
    final changeMonth =
        date.year != _focused.year || date.month != _focused.month;
    final cached = changeMonth ? _rangeCache[_monthKey(date)] : null;
    setState(() {
      _selected = DateTime(date.year, date.month, date.day);
      if (changeMonth) {
        _untimedExpanded = false;
        _otherTimeExpanded = false;
      }
      if (changeMonth) {
        _focused = DateTime(date.year, date.month, 1);
        // Neighboring dates are already loaded by the current date strip.
        // Reuse confirmed records rather than blanking the whole page.
        if (cached != null) {
          _data = cached;
          _loading = false;
          _loadFailed = false;
        }
      }
    });
    if (changeMonth) {
      _notifyHeader();
      if (cached == null) {
        await _load();
      } else if (_viewMode != CalendarViewMode.month) {
        await _ensureRange();
      }
    } else if (_viewMode != CalendarViewMode.month) {
      await _ensureRange();
    }
  }

  Future<void> _addTask(DateTime date, {TimeOfDay? time}) async {
    await _selectDate(date);
    if (!mounted) return;
    if (widget.createTaskOverride != null) {
      await widget.createTaskOverride!(context, date);
      await _refresh();
      return;
    }
    if (SlowlightPlatformDensity.usesMobileTouchTargets) {
      await TaskDetailSheet.showCreate(
        context,
        lists: widget.createListsOverride,
        initialDueDate: date,
        initialDueTime: time,
        defaultDueToday: false,
        onChanged: _refresh,
      );
      return;
    }
    final created = await TaskCreateSheet.showFullCreate(
      context,
      defaultDueDate: date,
      defaultToToday: false,
    );
    if (created == true && mounted) await _refresh();
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
    if (widget.headerInAppBar &&
        SlowlightPlatformDensity.usesMobileTouchTargets &&
        _viewMode != CalendarViewMode.month && _hasCurrentMonth) {
      return _pinnedClockView();
    }
    return FxRefresh(
      onRefresh: _refresh,
      child: ListView(
        key: const ValueKey('calendar-scroll-view'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          widget.headerInAppBar && SlowlightPlatformDensity.usesMobileTouchTargets ? 12 : 20,
          widget.headerInAppBar ? 4 : 18,
          widget.headerInAppBar && SlowlightPlatformDensity.usesMobileTouchTargets ? 12 : 20,
          32,
        ),
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
                      action: FxButton(label: '重新加载', onPressed: _refresh),
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
                      const SizedBox(height: 12),
                      if (widget.headerInAppBar &&
                          SlowlightPlatformDensity.usesMobileTouchTargets)
                        _compactMonthPanel()
                      else
                        _dayPanel(),
                    ] else ...[
                      // The shared date header is part of the time grid.
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
                        _timeGrid(),
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

  // Pin the same date rail used by the time-axis columns on Android.
  Widget _pinnedClockView() {
    return FxRefresh(
      onRefresh: _refresh,
      child: CustomScrollView(
        key: const ValueKey('calendar-scroll-view'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_hasCurrentMonth && _data!.unavailableTypes.isNotEmpty)
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _partialDataNotice(),
            )),
          if (_loadFailed && _hasCurrentMonth)
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _monthRefreshFailedNotice(),
            )),
          SliverPersistentHeader(
            pinned: true,
            delegate: _CalendarDateHeaderDelegate(
              height: 56,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _dateStrip(),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
              child: _rangeLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Center(child: FxCircularProgress()),
                    )
                  : _rangeFailed
                      ? FxEmptyState(
                          icon: LucideIcons.triangleAlert,
                          title: '部分日期读取失败',
                          subtitle: '跨月记录尚未核实，不能按无记录展示。',
                          action: FxButton(label: '重新加载',
                              onPressed: _retryRange),
                        )
                      : _timeGrid(includeDateStrip: false),
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


  // Clock modes share the same axis width and column count as the date rail.
  Widget _dateStrip() {
    final days = _visibleDays();
    final colors = Theme.of(context).colorScheme;
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return GestureDetector(
      key: const ValueKey('calendar-date-strip'),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() > 180) _shiftPeriod(velocity < 0 ? 1 : -1);
      },
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(
          bottom: BorderSide(color: colors.outlineVariant),
        )),
        child: Row(children: [
          const SizedBox(width: _calendarAxisWidth),
          for (final day in days)
            Expanded(child: FxInkWell(
              key: ValueKey('calendar-period-day-' + day.year.toString() +
                  '-' + day.month.toString() + '-' + day.day.toString()),
              onTap: () => _selectDate(day),
              child: Semantics(
                selected: _sameDay(day, _selected),
                label: day.month.toString() + '月' + day.day.toString() +
                    '日，周' + weekdays[day.weekday - 1] + '，' + _dateCount(day),
                child: SizedBox(height: 56, child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('周' + weekdays[day.weekday - 1],
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: SlowlightTypography.caption(context)),
                    const SizedBox(height: 2),
                    Container(
                      width: 27, height: 27,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _sameDay(day, _selected)
                            ? activePalette.accent : Colors.transparent,
                        border: _sameDay(day, DateTime.now()) &&
                                !_sameDay(day, _selected)
                            ? Border.all(color: activePalette.accent) : null,
                      ),
                      child: Text(day.day.toString(),
                        style: SlowlightTypography.caption(context).copyWith(
                          fontWeight: FontWeight.w700,
                          color: _sameDay(day, _selected)
                              ? colors.onPrimary
                              : _sameDay(day, DateTime.now())
                                  ? activePalette.accent : colors.onSurface,
                        )),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 3,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_timelineRecords(day).any(
                              (r) => r.kind == CalendarRecordKind.plan))
                            Container(
                              width: 3, height: 3,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: activePalette.accent,
                              ),
                            ),
                          if (_timelineRecords(day).any(
                              (r) => r.kind == CalendarRecordKind.actual)) ...[
                            const SizedBox(width: 3),
                            Container(
                              width: 3, height: 3,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.success,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                )),
              ),
            )),
        ]),
      ),
    );
  }

  String _dateCount(DateTime day) {
    final data = _rangeCache[_monthKey(day)];
    if (data == null) return '未读取';
    if (data.unavailableTypes.isNotEmpty) return '部分来源未核实';
    return _timelineRecords(day).length.toString() + ' 条';
  }

  // Native HH:mm only. Completion facts carry the trailing " 完成".
  int? _clockMinute(CalendarRecord record) {
    final match = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)(?: 完成)?$')
        .firstMatch(record.timeLabel);
    if (match == null) return null;
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  List<CalendarRecord> _timelineRecords(DateTime day) {
    final source = _rangeCache[_monthKey(day)];
    if (source == null) return const [];
    final records = source.records.where((record) {
      if (!_sameDay(record.date, day)) return false;
      return switch (_displayMode) {
        CalendarDisplayMode.all => true,
        CalendarDisplayMode.plan => record.kind == CalendarRecordKind.plan,
        CalendarDisplayMode.actual => record.kind == CalendarRecordKind.actual,
      };
    }).toList();
    records.sort((a, b) =>
        (_clockMinute(a) ?? 1440).compareTo(_clockMinute(b) ?? 1440));
    return records;
  }

  String _timeText(int value) =>
      (value ~/ 60).toString().padLeft(2, '0') + ':' +
      (value % 60).toString().padLeft(2, '0');

  bool _isTimed(CalendarRecord record) {
    final minute = _clockMinute(record);
    return minute != null &&
        minute >= _calendarStartMinute && minute < _calendarEndMinute;
  }

  Future<void> _addAt(DateTime day, double y) async {
    final halves = (y / (_calendarHourHeight / 2)).floor();
    final minute = (_calendarStartMinute + halves * 30)
        .clamp(_calendarStartMinute, _calendarEndMinute - 30).toInt();
    await _addTask(day, time: TimeOfDay(
      hour: minute ~/ 60, minute: minute % 60,
    ));
  }

  Future<void> _proposeMove(
      CalendarRecord record, DateTime day, int minute) async {
    if (record.kind != CalendarRecordKind.plan || record.task == null) return;
    if (_sameDay(day, record.date) && minute == _clockMinute(record)) return;
    // Reuse the canonical editor: moving is an unsaved draft until confirmed.
    await TaskDetailSheet.show(context,
      task: record.task!,
      lists: widget.createListsOverride ?? const <TodoList>[],
      initialDueDate: day,
      initialDueTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
      onChanged: _refresh,
    );
  }

  Widget _timeGrid({bool includeDateStrip = true}) {
    final days = _visibleDays();
    if (days.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final untimed = <CalendarRecord>[];
    final outsideHours = <CalendarRecord>[];
    for (final day in days) {
      for (final record in _timelineRecords(day)) {
        if (_isTimed(record)) continue;
        if (_clockMinute(record) == null) {
          untimed.add(record);
        } else {
          outsideHours.add(record);
        }
      }
    }
    final partial = days.any((d) =>
        _rangeCache[_monthKey(d)]?.unavailableTypes.isNotEmpty ?? false);
    return Column(
      key: const ValueKey('calendar-selected-timeline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (includeDateStrip) _dateStrip(),
        if (partial) Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('部分来源未核实，仍保留已确认的记录。',
            style: SlowlightTypography.caption(context)),
        ),
        LayoutBuilder(builder: (context, constraints) {
          final colWidth =
              (constraints.maxWidth - _calendarAxisWidth) / days.length;
          return SizedBox(
            height: 14 * _calendarHourHeight,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: _calendarAxisWidth, child: Stack(children: [
                  for (var hour = 8; hour < 22; hour++)
                    Positioned(top: (hour - 8) * _calendarHourHeight,
                      right: 4, child: Transform.translate(
                        offset: const Offset(0, -6),
                        child: Text(hour.toString().padLeft(2, '0') + ':00',
                          style: SlowlightTypography.caption(context).copyWith(
                            fontSize: 9, color: colors.onSurfaceVariant)))),
                ])),
                for (var i = 0; i < days.length; i++)
                  Expanded(child: _timeColumn(days, i, colWidth)),
              ],
            ),
          );
        }),
        if (untimed.isNotEmpty) _remainingRecords(untimed),
        if (outsideHours.isNotEmpty) _remainingRecords(outsideHours, outside: true),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FxButton(
              key: const ValueKey('calendar-period-add-task'),
              label: '安排任务',
              icon: LucideIcons.plus,
              size: FxButtonSize.sm,
              variant: FxButtonVariant.outline,
              onPressed: () => _addTask(_selected),
            ),
          ),
        ),
      ],
    );
  }

  Widget _timeColumn(List<DateTime> days, int index, double width) {
    final day = days[index];
    final colors = Theme.of(context).colorScheme;
    final records = _timelineRecords(day).where(_isTimed).toList();
    return Stack(clipBehavior: Clip.hardEdge, children: [
      for (var hour = 0; hour < 14; hour++)
        Positioned(top: hour * _calendarHourHeight, left: 0, right: 0,
          child: Container(height: 1,
            color: colors.outlineVariant.withValues(alpha: .4))),
      Positioned.fill(child: GestureDetector(
        key: ValueKey('calendar-hour-slot-' + day.year.toString() +
            '-' + day.month.toString() + '-' + day.day.toString()),
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) => _addAt(day, details.localPosition.dy),
        child: const SizedBox.expand(),
      )),
      for (final record in records) _timeBlock(record, days, index, width),
    ]);
  }

  Widget _timeBlock(
      CalendarRecord record, List<DateTime> days, int index, double width) {
    final minute = _clockMinute(record)!;
    final top = ((minute - _calendarStartMinute) *
        _calendarHourHeight / 60).clamp(0.0, 732.0).toDouble();
    // Start-only tasks are short markers, not invented one-hour meetings.
    final rawHeight = record.durationMin > 0
        ? (record.durationMin * _calendarHourHeight / 60)
            .clamp(25.0, 180.0).toDouble()
        : 33.0;
    final height = rawHeight.clamp(24.0, 756.0 - top).toDouble();
    final color = calendarRecordColor(record, context);
    final canMove = record.kind == CalendarRecordKind.plan &&
        record.task != null;
    return Positioned(left: 2, right: 2, top: top, height: height,
      child: Transform.translate(
        offset: _draggingRecordId == record.id ? _dragOffset : Offset.zero,
        child: GestureDetector(
          onLongPressStart: canMove ? (details) => setState(() {
            _draggingRecordId = record.id;
            _dragOrigin = details.globalPosition;
            _dragOffset = Offset.zero;
          }) : null,
          onLongPressMoveUpdate: canMove ? (details) => setState(() {
            _dragOffset = details.globalPosition - _dragOrigin;
          }) : null,
          onLongPressEnd: canMove ? (details) {
            final delta = details.globalPosition - _dragOrigin;
            setState(() {
              _draggingRecordId = null;
              _dragOffset = Offset.zero;
            });
            if (delta.distance < 8 || width <= 0) return;
            final nextIndex = (index + (delta.dx / width).round())
                .clamp(0, days.length - 1).toInt();
            final nextMinute = (minute +
                (delta.dy / _calendarHourHeight * 2).round() * 30)
                .clamp(_calendarStartMinute, _calendarEndMinute - 30).toInt();
            _proposeMove(record, days[nextIndex], nextMinute);
          } : null,
          child: FxInkWell(
            key: ValueKey('calendar-timeline-record-' + record.id),
            onTap: () => _openRecord(record),
            child: Semantics(
              label: record.title + '，' + _timeText(minute) +
                  (record.durationMin > 0
                      ? '，' + record.durationMin.toString() + '分钟'
                      : '，未指定结束时间'),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .13),
                  border: Border(left: BorderSide(
                    color: color, width: days.length == 7 ? 2 : 3)),
                  borderRadius: BorderRadius.circular(SlowlightRadius.sm),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    days.length == 7 ? 2 : 5, 3, 2, 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(record.title,
                        maxLines: height > 75 ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: SlowlightTypography.caption(context).copyWith(
                          fontWeight: FontWeight.w600)),
                      if (height > 90 && days.length <= 3 &&
                          MediaQuery.textScalerOf(context).scale(12) < 18)
                        Text(_timeText(minute),
                          style: SlowlightTypography.caption(context)
                              .copyWith(color: color)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _remainingRecords(List<CalendarRecord> rows, {bool outside = false}) {
    final colors = Theme.of(context).colorScheme;
    final expanded = outside ? _otherTimeExpanded : _untimedExpanded;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FxInkWell(
        key: ValueKey(outside ? 'calendar-other-time-toggle' : 'calendar-untimed-toggle'),
        onTap: () => setState(() {
          if (outside) {
            _otherTimeExpanded = !_otherTimeExpanded;
          } else {
            _untimedExpanded = !_untimedExpanded;
          }
        }),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(children: [
            Text(outside ? '其他时间' : '未定时间',
              style: SlowlightTypography.secondary(context)
                  .copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Text(rows.length.toString() + ' 项',
              style: SlowlightTypography.caption(context)),
            const Spacer(),
            Icon(expanded
                ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 16, color: colors.onSurfaceVariant),
          ]),
        ),
      ),
      if (expanded)
        for (final record in rows)
          FxInkWell(
            key: ValueKey('calendar-untimed-record-' + record.id),
            onTap: () => _openRecord(record),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(children: [
                Expanded(child: Text(record.title,
                  style: SlowlightTypography.secondary(context))),
                Text(record.timeLabel.isEmpty
                    ? '未指定' : record.timeLabel,
                  style: SlowlightTypography.caption(context)),
              ]),
            ),
          ),
    ]);
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
          onPressed: _loading ? null : _refresh,
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
            onPressed: _loading ? null : _refresh,
          ),
        ]),
      ),
    );
  }

  // Android month overview reuses records and detail editor in a compact list.
  Widget _compactMonthPanel() {
    final rows = _recordsForDay(_selected);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final theme = Theme.of(context);
    final plans = rows.where((r) => r.kind == CalendarRecordKind.plan).length;
    final actual = rows.where((r) => r.kind == CalendarRecordKind.actual).length;
    return Column(
      key: _dayPanelKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _selected.month.toString() + '月' + _selected.day.toString() +
                    '日 · 周' + weekdays[_selected.weekday - 1],
                key: const ValueKey('calendar-selected-title'),
                style: SlowlightTypography.secondary(context)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                _hasCurrentMonth && _data!.unavailableTypes.isNotEmpty
                    ? '已载入 ' + rows.length.toString() + ' 条 · 部分待核对'
                    : plans.toString() + ' 项计划 · ' +
                        actual.toString() + ' 条记录',
                style: SlowlightTypography.caption(context)
                    .copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          )),
          FxIconButton(
            key: const ValueKey('calendar-add-task'),
            icon: LucideIcons.plus,
            tooltip: '安排任务',
            onPressed: () => _addTask(_selected),
          ),
        ]),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              _hasCurrentMonth && _data!.unavailableTypes.isNotEmpty
                  ? '部分记录待核对'
                  : '当天还没有安排或记录',
              textAlign: TextAlign.center,
              style: SlowlightTypography.caption(context)
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          )
        else
          for (final record in rows)
            FxInkWell(
              key: ValueKey('calendar-record-' + record.id),
              onTap: () => _openRecord(record),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: .6),
                  )),
                ),
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  SizedBox(width: 40,
                    child: Text(
                      _clockMinute(record) == null
                          ? '未定' : _timeText(_clockMinute(record)!),
                      style: SlowlightTypography.caption(context),
                    )),
                  const SizedBox(width: 7),
                  Container(width: 3, height: 24,
                    decoration: BoxDecoration(
                      color: calendarRecordColor(record, context),
                      borderRadius: BorderRadius.circular(SlowlightRadius.sm),
                    )),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    record.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SlowlightTypography.secondary(context),
                  )),
                ]),
              ),
            ),
      ],
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
        onChanged: _refresh,
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
