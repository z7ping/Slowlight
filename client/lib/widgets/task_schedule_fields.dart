import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../ui/fx.dart';

/// 完整新建与快捷展开共用的日程字段，避免维护两套日期/重复/提醒交互。
class TaskScheduleFields extends StatelessWidget {
  const TaskScheduleFields({
    super.key,
    required this.enabled,
    this.compact = false,
    required this.dueDate,
    required this.onDateChanged,
    required this.dueTime,
    required this.onTimeChanged,
    required this.repeatType,
    required this.onRepeatChanged,
    required this.selectedWeekdays,
    required this.onWeekdayToggled,
    required this.reminderAdvanceMinutes,
    required this.onReminderChanged,
    this.customReminderAt,
    this.onCustomReminderChanged,
  });

  final bool enabled;
  /// 仅改变手机端网格密度，不分叉日期、重复和提醒逻辑。
  final bool compact;
  final DateTime? dueDate;
  final ValueChanged<DateTime?> onDateChanged;
  final TimeOfDay? dueTime;
  final ValueChanged<TimeOfDay?> onTimeChanged;
  final String repeatType;
  final ValueChanged<String> onRepeatChanged;
  final Set<int> selectedWeekdays;
  final ValueChanged<int> onWeekdayToggled;
  final int reminderAdvanceMinutes;
  final ValueChanged<int> onReminderChanged;
  /// Independent reminder instant; does not depend on a task due date.
  final DateTime? customReminderAt;
  final ValueChanged<DateTime?>? onCustomReminderChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FxResponsiveFormGrid(
          minColumnWidth: compact ? 136 : 240,
          maxColumns: 2,
          horizontalGap: compact ? 8 : 12,
          children: [
            _dateField(context),
            _timeField(context),
            _repeatField(),
            _reminderField(context),
          ],
        ),
        if (onCustomReminderChanged != null) ...[
          SizedBox(height: compact ? 8 : 12),
          FxFormField(
            label: '指定提醒日期和时间',
            child: Row(
              children: [
                Expanded(
                  child: _picker(
                    key: const ValueKey('task-reminder-custom-picker'),
                    context: context,
                    text: customReminderAt == null
                        ? '选择日期和时间'
                        : _customReminderLabel(customReminderAt!),
                    icon: LucideIcons.bell,
                    onTap: () => _pickCustomReminder(context),
                  ),
                ),
                if (customReminderAt != null) ...[
                  const SizedBox(width: 4),
                  FxIconButton(
                    icon: LucideIcons.x,
                    tooltip: '清除指定提醒',
                    iconSize: 15,
                    onPressed: enabled
                        ? () => onCustomReminderChanged!(null)
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ],
        if (repeatType == 'weekly') ...[
          const SizedBox(height: 12),
          FxFormField(
            label: '每周重复',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(7, (index) {
                final day = index + 1;
                const labels = ['一', '二', '三', '四', '五', '六', '日'];
                return FxChoiceChip(
                  label: labels[index],
                  selected: selectedWeekdays.contains(day),
                  onTap: enabled ? () => onWeekdayToggled(day) : null,
                );
              }),
            ),
          ),
        ],
      ],
    );
  }

  Widget _dateField(BuildContext context) {
    return FxFormField(
      label: '到期日期',
      child: Row(
        children: [
          Expanded(child: _picker(
            context: context,
            text: dueDate == null ? '未设置' : _dateLabel(dueDate!),
            icon: LucideIcons.calendarDays,
            onTap: () async {
              final date = await showFxDatePicker(
                context: context,
                initialDate: dueDate ?? DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
              );
              if (date != null && context.mounted) onDateChanged(date);
            },
          )),
          if (dueDate != null) ...[
            const SizedBox(width: 4),
            FxIconButton(
              icon: LucideIcons.x,
              tooltip: '清除到期日期',
              iconSize: 15,
              onPressed: enabled ? () => onDateChanged(null) : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _timeField(BuildContext context) {
    return FxFormField(
      label: '时间',
      child: Row(
        children: [
          Expanded(child: _picker(
            context: context,
            text: dueTime == null ? '未设置' : formatTaskDueTime(dueTime)!,
            icon: LucideIcons.clock3,
            onTap: () async {
              final time = await showFxTimePicker(
                context: context,
                initialTime: dueTime ?? TimeOfDay.now(),
              );
              if (time != null && context.mounted) onTimeChanged(time);
            },
          )),
          if (dueTime != null) ...[
            const SizedBox(width: 4),
            FxIconButton(
              icon: LucideIcons.x,
              tooltip: '清除时间',
              iconSize: 15,
              onPressed: enabled ? () => onTimeChanged(null) : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _repeatField() {
    const labels = {
      'none': '不重复',
      'daily': '每天',
      'weekly': '每周',
      'monthly': '每月',
      'yearly': '每年',
    };
    return FxFormField(
      label: '重复',
      child: SizedBox(
        width: double.infinity,
        child: FxSelect<String>(
          value: repeatType,
          enabled: enabled,
          options: labels.entries
              .map((entry) => FxSelectOption<String>(
                value: entry.key,
                label: entry.value,
              ))
              .toList(growable: false),
          onChanged: (value) => onRepeatChanged(value ?? 'none'),
        ),
      ),
    );
  }

  Widget _reminderField(BuildContext context) {
    const values = <int, String>{
      -1: '不提醒',
      0: '准时',
      5: '提前 5 分钟',
      10: '提前 10 分钟',
      15: '提前 15 分钟',
      30: '提前 30 分钟',
      60: '提前 1 小时',
    };
    return FxFormField(
      label: dueDate == null ? '相对提醒（需到期日期）' : '提醒',
      child: FxSelect<int>(
          // Custom reminders are still valid without a task due date.
          value: customReminderAt != null
              ? -2
              : dueDate == null ? -1 : reminderAdvanceMinutes,
          enabled: enabled && dueDate != null,
          options: [
            if (customReminderAt != null)
              const FxSelectOption<int>(
                value: -2,
                label: '指定提醒日期和时间',
              ),
            ...values.entries.map((entry) => FxSelectOption<int>(
              value: entry.key,
              label: entry.value,
            )),
          ],
          onChanged: (value) {
            if (value == -2) {
              _pickCustomReminder(context);
            } else {
              onReminderChanged(value ?? -1);
            }
          },
        ),

    );
  }

  Future<void> _pickCustomReminder(BuildContext context) async {
    if (!enabled || onCustomReminderChanged == null) return;
    final date = await showFxDatePicker(
      context: context,
      initialDate: customReminderAt ?? dueDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (date == null || !context.mounted) return;
    final time = await showFxTimePicker(
      context: context,
      initialTime: customReminderAt == null
          ? (dueTime ?? TimeOfDay.now())
          : TimeOfDay.fromDateTime(customReminderAt!),
    );
    if (time == null || !context.mounted) return;
    onCustomReminderChanged!(DateTime(
      date.year, date.month, date.day, time.hour, time.minute,
    ));
  }

  String _customReminderLabel(DateTime value) {
    final date = value.year.toString() + '-' +
        value.month.toString().padLeft(2, '0') + '-' +
        value.day.toString().padLeft(2, '0');
    return date + ' ' + formatTaskDueTime(TimeOfDay.fromDateTime(value))!;
  }

  Widget _picker({
    Key? key,
    required BuildContext context,
    required String text,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return FxInkWell(
      key: key,
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(SlowlightRadius.md),
      hoverColor: theme.colorScheme.onSurface.withValues(alpha: .04),
      focusColor: activePalette.accent.withValues(alpha: .08),
      child: Container(
        constraints: BoxConstraints(minHeight: SlowlightPlatformDensity.inputMinHeight),
        padding: EdgeInsets.symmetric(
          horizontal: SlowlightPlatformDensity.inputHorizontalPadding,
        ),
        decoration: BoxDecoration(
          color: fxSurface(context),
          borderRadius: BorderRadius.circular(SlowlightRadius.md),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SlowlightTypography.componentControl(context),
              ),
            ),
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime value) {
    final now = DateTime.now();
    if (value.year == now.year &&
        value.month == now.month &&
        value.day == now.day) {
      return '今天';
    }
    return value.year.toString() + '-' +
        value.month.toString().padLeft(2, '0') + '-' +
        value.day.toString().padLeft(2, '0');
  }
}

String? formatTaskDueTime(TimeOfDay? time) {
  if (time == null) return null;
  return time.hour.toString().padLeft(2, '0') + ':' +
      time.minute.toString().padLeft(2, '0');
}

String formatTaskRepeatDays(String repeatType, Set<int> selectedWeekdays) {
  if (repeatType != 'weekly' || selectedWeekdays.isEmpty) return '';
  return (selectedWeekdays.toList()..sort()).join(',');
}

DateTime? buildTaskReminderAt({
  required DateTime? dueDate,
  required TimeOfDay? dueTime,
  required int advanceMinutes,
}) {
  if (advanceMinutes < 0 || dueDate == null) return null;
  final time = dueTime ?? const TimeOfDay(hour: 9, minute: 0);
  return DateTime(
    dueDate.year,
    dueDate.month,
    dueDate.day,
    time.hour,
    time.minute,
  ).subtract(Duration(minutes: advanceMinutes));
}
