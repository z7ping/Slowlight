import 'dart:ui' show FontFeature;
import 'package:slowlight/ui/fx.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/calendar_record.dart';
import '../theme/app_theme.dart';
import '../ui/typography_tokens.dart';

class CalendarMonthGrid extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime selectedDate;
  final List<CalendarRecord> records;
  final CalendarDisplayMode displayMode;
  final bool loading;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<DateTime> onAddTask;
  final ValueChanged<CalendarRecord> onOpenRecord;
  final ValueChanged<DateTime> onShowMore;

  const CalendarMonthGrid({
    super.key,
    required this.focusedMonth,
    required this.selectedDate,
    required this.records,
    required this.displayMode,
    required this.loading,
    required this.onSelectDate,
    required this.onAddTask,
    required this.onOpenRecord,
    required this.onShowMore,
  });

  bool _largeText(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(SlowlightTypography.captionSize) >=
      SlowlightTypography.captionSize * 1.3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final largeText = _largeText(context);
            final content = _monthContent(context, compact, largeText);

            // 360dp 等窄屏在大字体下无法同时容纳 7 个可读日期列。
            // 保留真实系统字号并让整个月格横向滚动，而不是压缩字体。
            if (compact && largeText && constraints.maxWidth < 560) {
              return SingleChildScrollView(
                key: const ValueKey('calendar-month-horizontal-scroll'),
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: 560, child: content),
              );
            }
            return content;
          },
        ),
      ),
    );
  }

  Widget _monthContent(BuildContext context, bool compact, bool largeText) {
    return Column(
      children: [
        _weekdayHeader(context),
        if (loading)
          const SizedBox(
            height: 560,
            child: Center(child: FxCircularProgress()),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 42,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: switch ((compact, largeText)) {
                (true, true) => 160.0,
                (true, false) => 112.0,
                (false, true) => 172.0,
                (false, false) => 136.0,
              },
            ),
            itemBuilder:
                (context, index) =>
                    _dayCell(context, _dates[index], compact, largeText),
          ),
      ],
    );
  }

  List<DateTime> get _dates {
    final first = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final start = first.subtract(Duration(days: first.weekday - 1));
    return List.generate(42, (index) => start.add(Duration(days: index)));
  }

  Widget _weekdayHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WeekdayLabel('周一'),
          _WeekdayLabel('周二'),
          _WeekdayLabel('周三'),
          _WeekdayLabel('周四'),
          _WeekdayLabel('周五'),
          _WeekdayLabel('周六'),
          _WeekdayLabel('周日'),
        ],
      ),
    );
  }

  Widget _dayCell(
    BuildContext context,
    DateTime date,
    bool compact,
    bool largeText,
  ) {
    final theme = Theme.of(context);
    final outside = date.month != focusedMonth.month;
    final selected = _sameDay(date, selectedDate);
    final today = _sameDay(date, DateTime.now());
    final items = _visibleRecords(date);
    final previewCount = largeText ? 1 : (compact ? 2 : 3);
    final shown = items.take(previewCount).toList(growable: false);
    final remaining = items.length - shown.length;
    final dateHeaderHeight = largeText ? 38.0 : 23.0;

    return Material(
      color:
          selected
              ? activePalette.accent.withValues(alpha: .08)
              : outside
              ? theme.colorScheme.surfaceContainerLow.withValues(alpha: .55)
              : theme.colorScheme.surfaceContainerLowest,
      child: FxInkWell(
        onTap: () => onSelectDate(date),
        child: Container(
          key: ValueKey(
            'calendar-day-${DateFormat('yyyy-MM-dd').format(date)}',
          ),
          padding: EdgeInsets.fromLTRB(compact ? 4 : 7, 5, compact ? 4 : 7, 4),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: theme.colorScheme.outlineVariant),
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            boxShadow:
                selected
                    ? [
                      BoxShadow(
                        color: activePalette.accent,
                        spreadRadius: -1,
                        blurRadius: 0,
                      ),
                    ]
                    : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: dateHeaderHeight,
                child: Row(
                  children: [
                    Container(
                      constraints: BoxConstraints(
                        minWidth: largeText ? 34 : 22,
                        minHeight: largeText ? 34 : 22,
                      ),
                      alignment: Alignment.center,
                      decoration:
                          today
                              ? BoxDecoration(
                                shape: BoxShape.circle,
                                color: activePalette.accent,
                              )
                              : null,
                      child: Text(
                        '${date.day}',
                        maxLines: 1,
                        style: SlowlightTypography.caption(context).copyWith(
                          fontWeight:
                              selected || today
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                          color:
                              today
                                  ? Colors.white
                                  : outside
                                  ? theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: .55)
                                  : theme.colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (!compact)
                      FxTooltip(
                        message: '在这天新建任务',
                        child: InkResponse(
                          radius: 18,
                          onTap: () => onAddTask(date),
                          child: const SizedBox(
                            width: 28,
                            height: 28,
                            child: Icon(LucideIcons.plus, size: 14),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ...shown.map(
                (record) => _recordChip(context, record, compact, largeText),
              ),
              if (remaining > 0)
                FxInkWell(
                  onTap: () => onShowMore(date),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 3, top: 3),
                    child: Text(
                      '还有 $remaining 条记录',
                      maxLines: largeText ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: SlowlightTypography.caption(
                        context,
                      ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recordChip(
    BuildContext context,
    CalendarRecord record,
    bool compact,
    bool largeText,
  ) {
    final theme = Theme.of(context);
    final color = calendarRecordColor(record, context);
    final suffix = record.durationMin > 0 ? ' · ${record.durationMin}m' : '';
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Material(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: FxInkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          onTap: () => onOpenRecord(record),
          child: Container(
            key: ValueKey('calendar-grid-record-${record.id}'),
            width: double.infinity,
            constraints: BoxConstraints(minHeight: largeText ? 36 : 24),
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 6),
            child: Text(
              '${record.title}$suffix',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SlowlightTypography.caption(context).copyWith(
                color:
                    record.completed
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<CalendarRecord> _visibleRecords(DateTime date) => records
      .where((record) {
        if (!_sameDay(record.date, date)) return false;
        return switch (displayMode) {
          CalendarDisplayMode.all => true,
          CalendarDisplayMode.plan => record.kind == CalendarRecordKind.plan,
          CalendarDisplayMode.actual =>
            record.kind == CalendarRecordKind.actual,
        };
      })
      .toList(growable: false);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _WeekdayLabel extends StatelessWidget {
  final String label;

  const _WeekdayLabel(this.label);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 2,
        style: SlowlightTypography.caption(context).copyWith(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

Color calendarRecordColor(CalendarRecord record, BuildContext context) {
  final parsed = _parseColor(record.colorHex);
  if (parsed != null) return parsed;
  return switch (record.type) {
    CalendarRecordType.task => AppTheme.priorityColor(record.priority),
    CalendarRecordType.habit => AppTheme.success,
    CalendarRecordType.focus => const Color(0xFF8B5CF6),
    CalendarRecordType.reflection => AppTheme.warning,
  };
}

Color? _parseColor(String raw) {
  try {
    var hex = raw.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  } catch (_) {
    return null;
  }
}
