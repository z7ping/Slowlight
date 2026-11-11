import 'fx_cursor.dart';
import 'fx_button.dart';
import 'fx_icon_button.dart';
import 'fx_dialog.dart';
import 'fx_sheet.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:table_calendar/table_calendar.dart';
import '../app_theme.dart';
import '../typography_tokens.dart';
import '../layout_tokens.dart';

// ═══════════════════════════════════════════
// FxDatePicker — 统一的日期选择器（Android Sheet / Windows Dialog）
// ═══════════════════════════════════════════

/// 日历日选择：范围、初始选中和“今天/昨天”均按本地自然日判断。
Future<DateTime?> showFxDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = '选择日期',
}) {
  final first = DateUtils.dateOnly(firstDate ?? DateTime(2020));
  final last = DateUtils.dateOnly(lastDate ?? DateTime(2030));
  if (first.isAfter(last)) return Future<DateTime?>.value(null);
  final initial = DateUtils.dateOnly(initialDate);
  final safeInitial = initial.isBefore(first)
      ? first
      : initial.isAfter(last)
          ? last
          : initial;

  Widget picker(BuildContext ctx) => _FxDatePickerDialog(
        initialDate: safeInitial,
        firstDate: first,
        lastDate: last,
      );

  if (SlowlightPlatformDensity.usesMobileTouchTargets) {
    return FxSheet.show<DateTime>(
      context: context,
      title: Text(title),
      showCloseButton: true,
      padding: const EdgeInsets.all(SlowlightSpacing.xxxl),
      builder: picker,
    );
  }
  return FxDialog.raw<DateTime>(
    context: context,
    builder: (ctx) => ShadDialog(
      title: Text(title),
      child: picker(ctx),
    ),
  );
}

class _FxDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const _FxDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_FxDatePickerDialog> createState() => _FxDatePickerDialogState();
}

class _FxDatePickerDialogState extends State<_FxDatePickerDialog> {
  late DateTime _focusedMonth;
  late DateTime _selectedDate;

  static const _weekdayHeaders = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _focusedMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
  }

  bool _inRange(DateTime day) =>
      !day.isBefore(widget.firstDate) && !day.isAfter(widget.lastDate);

  List<DateTime> _daysInMonth(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final offset = firstDay.weekday - 1;
    final days = <DateTime>[
      for (int i = offset; i > 0; i--)
        firstDay.subtract(Duration(days: i)),
      for (int d = 1; d <= lastDay.day; d++)
        DateTime(month.year, month.month, d),
    ];
    while (days.length % 7 != 0) {
      days.add(days.last.add(const Duration(days: 1)));
    }
    return days;
  }

  Widget _buildMonthView(DateTime month) {
    final colors = Theme.of(context).colorScheme;
    final today = DateUtils.dateOnly(DateTime.now());
    final cellHeight = SlowlightPlatformDensity.usesMobileTouchTargets
        ? SlowlightControlSize.minTouchTarget
        : 36.0;
    final dayFont = SlowlightTypography.buttonSize;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: _weekdayHeaders.map((label) => Expanded(
            child: SizedBox(
              height: cellHeight,
              child: Center(child: Text(
                label,
                style: TextStyle(
                  fontSize: SlowlightTypography.secondarySize,
                  fontWeight: FontWeight.w500,
                  color: colors.onSurfaceVariant,
                ),
              )),
            ),
          )).toList(),
        ),
        ...List.generate(_daysInMonth(month).length ~/ 7, (week) {
          final days = _daysInMonth(month);
          return Row(
            children: days.skip(week * 7).take(7).map((day) {
              final current = day.year == month.year && day.month == month.month;
              final enabled = current && _inRange(day);
              final selected = enabled && isSameDay(day, _selectedDate);
              final isToday = enabled && isSameDay(day, today);
              if (!current) {
                return Expanded(child: SizedBox(height: cellHeight));
              }
              final textColor = selected
                  ? colors.surface
                  : enabled
                      ? colors.onSurface
                      : colors.onSurfaceVariant.withValues(alpha: 0.36);
              final visualSize = cellHeight - SlowlightSpacing.xs * 2;
              final dayKey = 'fx.date.day.${day.year}-${day.month}-${day.day}';
              return Expanded(
                child: Semantics(
                  label: '${day.year}年${day.month}月${day.day}日' +
                      (enabled ? '' : '，不可选择'),
                  enabled: enabled,
                  selected: selected,
                  button: true,
                  child: FxInkWell(
                    key: ValueKey(dayKey),
                    onTap: enabled
                        ? () => setState(() => _selectedDate = day)
                        : null,
                    child: SizedBox(
                      height: cellHeight,
                      child: Center(
                        child: Container(
                          width: visualSize,
                          height: visualSize,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected
                                ? colors.onSurface
                                : isToday
                                    ? colors.surfaceContainerHighest
                                    : null,
                            border: isToday && !selected
                                ? Border.all(color: colors.outlineVariant)
                                : null,
                          ),
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: dayFont,
                              fontWeight: selected || isToday
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: textColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  bool get _canGoPrev {
    final prev = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    return !prev.isBefore(DateTime(widget.firstDate.year, widget.firstDate.month));
  }

  bool get _canGoNext {
    final next = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    return !next.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month));
  }

  DateTime? get _quickDate {
    final today = DateUtils.dateOnly(DateTime.now());
    if (_inRange(today)) return today;
    final yesterday = today.subtract(const Duration(days: 1));
    return _inRange(yesterday) ? yesterday : null;
  }

  void _selectQuickDate() {
    final date = _quickDate;
    if (date == null) return;
    setState(() {
      _selectedDate = date;
      _focusedMonth = DateTime(date.year, date.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mobile = SlowlightPlatformDensity.usesMobileTouchTargets;
    final quick = _quickDate;
    return SizedBox(
      width: mobile ? double.infinity : 328,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              FxIconButton(
                icon: LucideIcons.chevronLeft,
                tooltip: '上个月',
                onPressed: _canGoPrev
                    ? () => setState(() => _focusedMonth =
                        DateTime(_focusedMonth.year, _focusedMonth.month - 1))
                    : null,
              ),
              Text(
                DateFormat('yyyy年M月').format(_focusedMonth),
                style: SlowlightTypography.cardTitle(context),
              ),
              FxIconButton(
                icon: LucideIcons.chevronRight,
                tooltip: '下个月',
                onPressed: _canGoNext
                    ? () => setState(() => _focusedMonth =
                        DateTime(_focusedMonth.year, _focusedMonth.month + 1))
                    : null,
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 170),
            child: KeyedSubtree(
              key: ValueKey('fx.date.month.${_focusedMonth.year}-${_focusedMonth.month}'),
              child: _buildMonthView(_focusedMonth),
            ),
          ),
          const SizedBox(height: SlowlightSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '可选日期：${DateFormat('M月d日').format(widget.firstDate)} — ${DateFormat('M月d日').format(widget.lastDate)}',
              style: SlowlightTypography.caption(context).copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: SlowlightSpacing.xxxl),
          Row(
            children: [
              if (quick != null)
                FxButton(
                  label: isSameDay(quick, DateTime.now()) ? '今天' : '昨天',
                  variant: FxButtonVariant.ghost,
                  onPressed: _selectQuickDate,
                ),
              const SizedBox(width: SlowlightSpacing.md),
              Expanded(
                child: FxButton(
                  label: '确定',
                  size: FxButtonSize.lg,
                  expanded: true,
                  onPressed: () => Navigator.of(context).pop(_selectedDate),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════
// FxTimePicker — ShadCN 时间选择器
// ═══════════════════════════════════════════

/// 显示时间选择弹窗，返回 TimeOfDay
Future<TimeOfDay?> showFxTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String title = '选择时间',
}) async {
  final initial = ShadTimeOfDay(
    hour: initialTime.hour,
    minute: initialTime.minute,
    second: 0,
  );

  ShadTimeOfDay selected = initial;

  final result = await showShadDialog<bool>(
    context: context,
    builder: (ctx) {
      return ShadDialog(
        title: Text(title),
        description: const Text('点击数字可直接输入'),
        child: SizedBox(
          width: 320,
          child: ShadTimePicker(
            initialValue: initial,
            hourLabel: const Text('时'),
            minuteLabel: const Text('分'),
            secondLabel: const Text('秒'),
            onChanged: (v) => selected = v,
          ),
        ),
        actions: [
          ShadButton.outline(
            child: const Text('取消'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ShadButton(
            child: const Text('确定'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      );
    },
  );

  if (result == true) {
    return TimeOfDay(hour: selected.hour, minute: selected.minute);
  }
  return null;
}

// ═══════════════════════════════════════════
// FxDateTimePicker — 日期+时间组合选择器
// ═══════════════════════════════════════════

/// 先选日期再选时间，返回合并后的 DateTime
Future<DateTime?> showFxDateTimePicker({
  required BuildContext context,
  required DateTime initialDateTime,
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  final date = await showFxDatePicker(
    context: context,
    initialDate: initialDateTime,
    firstDate: firstDate,
    lastDate: lastDate,
    title: '选择日期',
  );
  if (date == null || !context.mounted) return null;

  final time = await showFxTimePicker(
    context: context,
    initialTime: TimeOfDay(
      hour: initialDateTime.hour,
      minute: initialDateTime.minute,
    ),
  );
  if (time == null) return null;

  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

// ═══════════════════════════════════════════
// FxCalendar — 主题化日历视图组件
// ═══════════════════════════════════════════

class FxCalendar<T> extends StatelessWidget {
  final DateTime firstDay;
  final DateTime lastDay;
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final bool Function(DateTime)? selectedDayPredicate;
  final void Function(DateTime, DateTime)? onDaySelected;
  final void Function(DateTime)? onPageChanged;
  final List<T> Function(DateTime) eventLoader;
  final Widget Function(BuildContext, DateTime, List<T>)? markerBuilder;
  final String locale;

  const FxCalendar({
    super.key,
    required this.firstDay,
    required this.lastDay,
    required this.focusedDay,
    this.selectedDay,
    this.selectedDayPredicate,
    this.onDaySelected,
    this.onPageChanged,
    required this.eventLoader,
    this.markerBuilder,
    this.locale = 'zh_CN',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = isDark
        ? AppTheme.primaryLight
        : Theme.of(context).colorScheme.onSurface;

    // TableCalendar 的日期点击内部使用 InkResponse；Sheet 路由没有 Material
    // 表面，适配层在这里提供透明承载，不引入另一套日历视觉。
    return Material(
      type: MaterialType.transparency,
      child: TableCalendar<T>(
      firstDay: firstDay,
      lastDay: lastDay,
      focusedDay: focusedDay,
      selectedDayPredicate: selectedDayPredicate ??
          (day) => selectedDay != null ? isSameDay(selectedDay!, day) : false,
      locale: locale,
      // TableCalendar 默认星期行只有 16dp，系统大字号会裁切中文星期。
      daysOfWeekHeight: MediaQuery.textScalerOf(context)
              .scale(SlowlightTypography.buttonSize * 1.5) +
          SlowlightSpacing.xs,
      startingDayOfWeek: StartingDayOfWeek.monday,
      headerStyle: HeaderStyle(
        titleCentered: true,
        formatButtonVisible: false,
        headerMargin: const EdgeInsets.only(bottom: 0),
        headerPadding: const EdgeInsets.symmetric(vertical: 2),
        titleTextFormatter: (date, locale) =>
            '${date.year}年${date.month}月',
        titleTextStyle: TextStyle(
          fontSize: SlowlightTypography.bodySize,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        leftChevronIcon:
            Icon(LucideIcons.chevronLeft, color: AppTheme.warmGray500),
        rightChevronIcon:
            Icon(LucideIcons.chevronRight, color: AppTheme.warmGray500),
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: TextStyle(
          fontSize: SlowlightTypography.buttonSize,
          fontWeight: FontWeight.w500,
          color: AppTheme.warmGray500,
          height: 1.5,
        ),
        weekendStyle: TextStyle(
          fontSize: SlowlightTypography.buttonSize,
          fontWeight: FontWeight.w500,
          color: AppTheme.priorityHigh,
          height: 1.5,
        ),
      ),
      calendarStyle: CalendarStyle(
        outsideDaysVisible: false,
        defaultTextStyle: TextStyle(
          fontSize: SlowlightTypography.buttonSize,
          fontWeight: FontWeight.w500,
          color: onSurface,
          height: 1.5,
        ),
        weekendTextStyle: TextStyle(
          fontSize: SlowlightTypography.buttonSize,
          fontWeight: FontWeight.w500,
          color: AppTheme.priorityHigh,
          height: 1.5,
        ),
        todayDecoration: BoxDecoration(
          color: AppTheme.primaryLight,
          shape: BoxShape.circle,
        ),
        todayTextStyle: TextStyle(
          fontSize: SlowlightTypography.buttonSize,
          fontWeight: FontWeight.w600,
          color: AppTheme.primary,
          height: 1.5,
        ),
        selectedDecoration: BoxDecoration(
          color: AppTheme.primary,
          shape: BoxShape.circle,
        ),
        selectedTextStyle: const TextStyle(
          fontSize: SlowlightTypography.buttonSize,
          fontWeight: FontWeight.w600,
          color: AppTheme.white,
          height: 1.5,
        ),
        tablePadding: EdgeInsets.zero,
      ),
      eventLoader: eventLoader,
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      calendarBuilders: CalendarBuilders(
        markerBuilder: markerBuilder,
      ),
      ),
    );
  }
}
