import 'fx_cursor.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:table_calendar/table_calendar.dart';
import '../app_theme.dart';
import '../typography_tokens.dart';

// ═══════════════════════════════════════════
// FxDatePicker — ShadCN 风格日期选择器
// ═══════════════════════════════════════════

/// 显示日期选择弹窗
Future<DateTime?> showFxDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = '选择日期',
}) async {
  final result = await showShadDialog<DateTime>(
    context: context,
    builder: (ctx) {
      return _FxDatePickerDialog(
        initialDate: initialDate,
        firstDate: firstDate ?? DateTime(2020),
        lastDate: lastDate ?? DateTime(2030),
        title: title,
      );
    },
  );
  return result;
}

class _FxDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;

  const _FxDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.title,
  });

  @override
  State<_FxDatePickerDialog> createState() => _FxDatePickerDialogState();
}

class _FxDatePickerDialogState extends State<_FxDatePickerDialog> {
  late DateTime _focusedMonth;
  DateTime? _selectedDate;

  static const _weekdayHeaders = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _focusedMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
  }

  List<DateTime> _daysInMonth(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final startOffset = (firstDay.weekday - 1) % 7;
    final days = <DateTime>[];
    for (int i = 0; i < startOffset; i++) {
      days.add(firstDay.subtract(Duration(days: startOffset - i)));
    }
    for (int d = 1; d <= lastDay.day; d++) {
      days.add(DateTime(month.year, month.month, d));
    }
    while (days.length % 7 != 0) {
      days.add(days.last.add(const Duration(days: 1)));
    }
    return days;
  }

  Widget _buildMonthView(DateTime month) {
    final days = _daysInMonth(month);
    final today = DateTime.now();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.primaryLight : AppTheme.warmGray500;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: _weekdayHeaders.map((d) {
              final isWeekend = d == '六' || d == '日';
              return Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: TextStyle(
                      fontSize: SlowlightTypography.secondarySize,
                      fontWeight: FontWeight.w500,
                      color: isWeekend
                          ? AppTheme.priorityHigh.withValues(alpha: 0.7)
                          : textColor.withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        ...List.generate(days.length ~/ 7, (week) {
          final weekDays = days.skip(week * 7).take(7).toList();
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: weekDays.map((day) {
                final isCurrentMonth = day.month == month.month;
                final isSelected =
                    _selectedDate != null && isSameDay(day, _selectedDate!);
                final isToday = isSameDay(day, today);
                final isWeekend = day.weekday == DateTime.saturday ||
                    day.weekday == DateTime.sunday;
                final isDisabled = day.isBefore(widget.firstDate) ||
                    day.isAfter(widget.lastDate);

                Color? bgColor;
                Color fgColor;

                if (isSelected) {
                  bgColor = AppTheme.primary;
                  fgColor = AppTheme.white;
                } else if (isToday) {
                  bgColor = AppTheme.primaryLight;
                  fgColor = AppTheme.primary;
                } else if (!isCurrentMonth) {
                  fgColor = textColor.withValues(alpha: 0.25);
                } else if (isDisabled) {
                  fgColor = textColor.withValues(alpha: 0.3);
                } else if (isWeekend) {
                  fgColor = AppTheme.priorityHigh.withValues(alpha: .82);
                } else {
                  fgColor = textColor;
                }

                return Expanded(
                  child: FxGestureDetector(
                    onTap: (!isDisabled && isCurrentMonth)
                        ? () => setState(() => _selectedDate = day)
                        : null,
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: bgColor,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: SlowlightTypography.buttonSize,
                            fontWeight: isSelected || isToday
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: fgColor,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
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

  bool get _canPickToday {
    final today = DateTime.now();
    final date = DateTime(today.year, today.month, today.day);
    final first = DateTime(
      widget.firstDate.year,
      widget.firstDate.month,
      widget.firstDate.day,
    );
    final last = DateTime(
      widget.lastDate.year,
      widget.lastDate.month,
      widget.lastDate.day,
    );
    return !date.isBefore(first) && !date.isAfter(last);
  }

  void _goPrev() {
    if (!_canGoPrev) return;
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    });
  }

  void _goNext() {
    if (!_canGoNext) return;
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    });
  }

  void _pickToday() {
    if (!_canPickToday) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _selectedDate = today;
      _focusedMonth = DateTime(today.year, today.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.primaryLight : AppTheme.warmGray500;

    return ShadDialog(
      title: Text(widget.title),
      child: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  enabled: _canGoPrev,
                  onPressed: _goPrev,
                  child: const Icon(Icons.chevron_left, size: 20),
                ),
                Text(
                  DateFormat('yyyy年M月').format(_focusedMonth),
                  style: TextStyle(
                    fontSize: SlowlightTypography.buttonSize,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  enabled: _canGoNext,
                  onPressed: _goNext,
                  child: const Icon(Icons.chevron_right, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: _buildMonthView(_focusedMonth),
            ),
          ],
        ),
      ),
      actions: [
        ShadButton.ghost(
          enabled: _canPickToday,
          onPressed: _pickToday,
          child: const Text('今天'),
        ),
        const SizedBox(width: 8),
        ShadButton(
          onPressed: () =>
              Navigator.of(context).pop(_selectedDate ?? widget.initialDate),
          child: const Text('确定'),
        ),
      ],
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

    return TableCalendar<T>(
      firstDay: firstDay,
      lastDay: lastDay,
      focusedDay: focusedDay,
      selectedDayPredicate: selectedDayPredicate ??
          (day) => selectedDay != null ? isSameDay(selectedDay!, day) : false,
      locale: locale,
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
            Icon(Icons.chevron_left, color: AppTheme.warmGray500),
        rightChevronIcon:
            Icon(Icons.chevron_right, color: AppTheme.warmGray500),
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
    );
  }
}
