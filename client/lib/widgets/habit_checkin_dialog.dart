import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/habit.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../ui/widgets/fx_cursor.dart';
import '../ui/widgets/fx_input.dart';

class HabitCheckinDialog extends StatefulWidget {
  final Habit habit;

  const HabitCheckinDialog({super.key, required this.habit});

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required Habit habit,
  }) {
    return FxSheet.show(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => HabitCheckinDialog(habit: habit),
    );
  }

  @override
  State<HabitCheckinDialog> createState() => _HabitCheckinDialogState();
}

class _HabitCheckinDialogState extends State<HabitCheckinDialog> {
  late int _durationMin;
  late String _period;
  final _noteController = TextEditingController();

  static const _periods = [
    {'value': '', 'label': '不限'},
    {'value': 'morning', 'label': '☀️ 早晨'},
    {'value': 'afternoon', 'label': '下午'},
    {'value': 'evening', 'label': '傍晚'},
    {'value': 'night', 'label': '🌙 晚间'},
  ];

  static const _durations = [5, 10, 15, 20, 30, 45, 60, 90, 120];

  @override
  void initState() {
    super.initState();
    _durationMin = widget.habit.durationMin > 0 ? widget.habit.durationMin : 30;
    _period = widget.habit.preferredPeriod;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return SafeArea(
      top: false,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      widget.habit.icon,
                      style: const TextStyle(fontSize: AppTheme.text2Xl),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.habit.name,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (mobile)
                      Text(
                        '下滑关闭',
                        style: TextStyle(
                          fontSize: AppTheme.textXs,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _label('实际时长'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _durations.map((duration) {
                    return _PickChip(
                      label: '$duration',
                      suffix: mobile ? '分' : '分钟',
                      selected: _durationMin == duration,
                      onTap: () => setState(() => _durationMin = duration),
                    );
                  }).toList(growable: false),
                ),
                const SizedBox(height: 12),
                _label('时间段'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _periods.map((period) {
                    final value = period['value'] as String;
                    return _PickChip(
                      label: period['label'] as String,
                      selected: _period == value,
                      onTap: () => setState(() => _period = value),
                    );
                  }).toList(growable: false),
                ),
                const SizedBox(height: 12),
                FxInput(
                  controller: _noteController,
                  maxLines: 2,
                  placeholder: mobile ? '备注…' : '记录一下感受或收获...',
                ),
                const SizedBox(height: 12),
                if (mobile)
                  FxButton(
                    label: '记录打卡',
                    expanded: true,
                    onPressed: _submit,
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: FxButton(
                          label: '取消',
                          variant: FxButtonVariant.outline,
                          expanded: true,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FxButton(
                          label: '记录打卡',
                          expanded: true,
                          onPressed: _submit,
                        ),
                      ),
                    ],
                  ),
                if (mobile) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      '键盘弹出时会自动避让',
                      style: TextStyle(
                        fontSize: AppTheme.textXs,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    HapticFeedback.lightImpact();
    Navigator.pop(context, {
      'duration_min': _durationMin,
      'period': _period,
      'note': _noteController.text.trim(),
    });
  }

  Widget _label(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: AppTheme.textXs,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _PickChip extends StatelessWidget {
  final String label;
  final String? suffix;
  final bool selected;
  final VoidCallback onTap;

  const _PickChip({
    required this.label,
    this.suffix,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = activePalette.accent;
    return FxGestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: .12)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accent : theme.colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: AppTheme.textMd,
                fontWeight: FontWeight.w600,
                color: selected ? accent : theme.colorScheme.onSurface,
              ),
            ),
            if (suffix != null) ...[
              const SizedBox(width: 3),
              Text(
                suffix!,
                style: TextStyle(
                  fontSize: AppTheme.textXs,
                  color: selected ? accent : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
