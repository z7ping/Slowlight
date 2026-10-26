import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/habit.dart';
import '../ui/fx.dart';

/// 同一份记录表单：Android 底部弹层，Windows 居中对话框。
/// 显示字段只由 Habit 的 recordType/recordTimeLabel 决定，与名称无关。
class HabitCheckinDialog extends StatefulWidget {
  final Habit habit;
  final DateTime? recordDate;
  final Future<void> Function(Map<String, dynamic>)? onSubmit;
  final Map<String, dynamic>? pendingValue;
  final String? initialError;

  const HabitCheckinDialog(
      {super.key,
      required this.habit,
      this.recordDate,
      this.onSubmit,
      this.pendingValue,
      this.initialError});

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required Habit habit,
    DateTime? recordDate,
    Future<void> Function(Map<String, dynamic>)? onSubmit,
    Map<String, dynamic>? pendingValue,
    String? initialError,
  }) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      return FxSheet.show<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        showCloseButton: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SlowlightRadius.sheet),
          ),
        ),
        builder: (_) => HabitCheckinDialog(
            habit: habit,
            recordDate: recordDate,
            onSubmit: onSubmit,
            pendingValue: pendingValue,
            initialError: initialError),
      );
    }
    return FxDialog.raw<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FxDialogSurface(
        showCloseButton: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SlowlightRadius.xl),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: HabitCheckinDialog(
              habit: habit,
              recordDate: recordDate,
              onSubmit: onSubmit,
              pendingValue: pendingValue,
              initialError: initialError),
        ),
      ),
    );
  }

  @override
  State<HabitCheckinDialog> createState() => _HabitCheckinDialogState();
}

class _HabitCheckinDialogState extends State<HabitCheckinDialog> {
  late int _durationMin;
  late String _period;
  late TimeOfDay _occurredTime;
  final _note = TextEditingController();
  final _count = TextEditingController(text: '1');
  String? _error;
  bool _submitting = false;
  Map<String, dynamic>? _pendingValue;

  static const _periods = <(String, String)>[
    ('', '不限'),
    ('morning', '早晨'),
    ('afternoon', '下午'),
    ('evening', '傍晚'),
    ('night', '晚间'),
  ];
  static const _durations = [5, 10, 15, 20, 30, 45, 60, 90, 120];

  bool get _usesDuration =>
      widget.habit.recordType == 'duration' ||
      widget.habit.recordType == 'legacy';
  bool get _usesPeriod =>
      widget.habit.recordType == 'duration' ||
      widget.habit.recordType == 'legacy';

  @override
  void initState() {
    super.initState();
    _durationMin = widget.habit.durationMin > 0 ? widget.habit.durationMin : 30;
    _period = widget.habit.preferredPeriod;
    _occurredTime = TimeOfDay.fromDateTime(DateTime.now());
    _pendingValue = widget.pendingValue;
    _error = widget.initialError;
    if (_pendingValue case final value?) {
      _note.text = value['note']?.toString() ?? '';
      _count.text = value['count_value']?.toString() ?? '1';
      _durationMin = value['duration_min'] as int? ?? _durationMin;
      _period = value['period']?.toString() ?? _period;
      final occurred =
          DateTime.tryParse(value['occurred_at']?.toString() ?? '');
      if (occurred != null) {
        _occurredTime = TimeOfDay.fromDateTime(occurred.toLocal());
      }
    }
  }

  @override
  void dispose() {
    _note.dispose();
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mobile = theme.platform == TargetPlatform.android ||
        theme.platform == TargetPlatform.iOS;
    return PopScope(
      canPop: !_submitting,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding:
              EdgeInsets.fromLTRB(mobile ? 16 : 20, 16, mobile ? 16 : 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(widget.habit.icon,
                      style: const TextStyle(
                          fontSize: SlowlightTypography.pageTitleSize)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(widget.habit.name,
                        style: SlowlightTypography.cardTitle(context)),
                  ),
                ],
              ),
              if (widget.recordDate case final day?) ...[
                const SizedBox(height: SlowlightSpacing.xs),
                Text('记录日期：${day.year}年${day.month}月${day.day}日',
                    style: SlowlightTypography.secondary(context)),
              ],
              const SizedBox(height: 16),
              ExcludeFocus(
                  excluding: _submitting || _pendingValue != null,
                  child: AbsorbPointer(
                      absorbing: _submitting || _pendingValue != null,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_usesDuration) ...[
                              _label('实际时长（分钟）'),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _durations
                                    .map((value) => FxChoiceChip(
                                          label: '$value 分钟',
                                          selected: _durationMin == value,
                                          onTap: () => setState(() {
                                            _durationMin = value;
                                            _error = null;
                                          }),
                                        ))
                                    .toList(),
                              ),
                              const SizedBox(height: 14),
                            ],
                            if (widget.habit.recordType == 'count') ...[
                              FxInput(
                                controller: _count,
                                label: '完成次数（${widget.habit.recordUnit}）',
                                keyboardType: TextInputType.number,
                                errorText:
                                    _pendingValue == null ? _error : null,
                                onChanged: (_) => setState(() => _error = null),
                              ),
                              const SizedBox(height: 14),
                            ],
                            if (widget.habit.recordTimeLabel.isNotEmpty) ...[
                              _label(widget.habit.recordTimeLabel),
                              const SizedBox(height: 8),
                              FxButton(
                                label:
                                    '${_occurredTime.hour.toString().padLeft(2, '0')}:${_occurredTime.minute.toString().padLeft(2, '0')}',
                                variant: FxButtonVariant.outline,
                                onPressed: () async {
                                  final picked = await showFxTimePicker(
                                    context: context,
                                    initialTime: _occurredTime,
                                  );
                                  if (picked != null && mounted) {
                                    setState(() {
                                      _occurredTime = picked;
                                      _error = null;
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 14),
                            ],
                            if (_usesPeriod) ...[
                              _label('时间段'),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _periods
                                    .map((item) => FxChoiceChip(
                                          label: item.$2,
                                          selected: _period == item.$1,
                                          onTap: () =>
                                              setState(() => _period = item.$1),
                                        ))
                                    .toList(),
                              ),
                              const SizedBox(height: 14),
                            ],
                            FxInput(
                              controller: _note,
                              label: '备注（选填）',
                              maxLines: 2,
                              placeholder: widget.recordDate == null
                                  ? '记录今天的感受……'
                                  : '记录这一天的感受……',
                            ),
                          ]))),
              if (_error != null &&
                  (widget.habit.recordType != 'count' ||
                      _pendingValue != null)) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: SlowlightSpacing.md,
                runSpacing: SlowlightSpacing.md,
                children: [
                  FxButton(
                      label: '取消',
                      variant: FxButtonVariant.outline,
                      onPressed:
                          _submitting ? null : () => Navigator.pop(context)),
                  SizedBox(
                    width: mobile ? double.infinity : null,
                    child: FxButton(
                      key: const ValueKey('habit-checkin-primary-action'),
                      label: _submitLabel,
                      expanded: mobile,
                      size: mobile ? FxButtonSize.lg : FxButtonSize.md,
                      onPressed: _submitting ? null : _submit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _submitLabel => _submitting
      ? '保存中…'
      : _pendingValue != null
          ? '重试保存'
          : widget.recordDate == null
              ? '确认打卡'
              : '确认补卡';

  Future<void> _submit() async {
    if (_submitting) return;
    if (_pendingValue case final value?) {
      await _save(value);
      return;
    }
    int? countValue;
    if (widget.habit.recordType == 'count') {
      countValue = int.tryParse(_count.text.trim());
      if (countValue == null || countValue <= 0) {
        setState(() => _error = '请填写大于 0 的实际次数');
        return;
      }
    }
    String? occurredAt;
    if (widget.habit.recordTimeLabel.isNotEmpty) {
      final now = DateTime.now();
      final day = widget.recordDate ?? now;
      final chosen = DateTime(
        day.year,
        day.month,
        day.day,
        _occurredTime.hour,
        _occurredTime.minute,
      );
      if (chosen.isAfter(now)) {
        setState(() => _error = '实际时间不能晚于当前时间');
        return;
      }
      occurredAt = chosen.toUtc().toIso8601String();
    }
    HapticFeedback.lightImpact();
    await _save({
      if (_usesDuration) 'duration_min': _durationMin,
      if (_usesPeriod) 'period': _period,
      if (countValue != null) 'count_value': countValue,
      if (occurredAt != null) 'occurred_at': occurredAt,
      'note': _note.text.trim(),
    });
  }

  Future<void> _save(Map<String, dynamic> value) async {
    if (widget.onSubmit == null) {
      Navigator.pop(context, value);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit!(value);
      if (!mounted) return;
      setState(() => _submitting = false);
      Navigator.pop(context, value);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _pendingValue = Map<String, dynamic>.unmodifiable(value);
        _error = '保存结果未确认，输入已保留。可重试保存；关闭后请先核对明细，避免重复记录。';
      });
    }
  }

  Widget _label(String title) => Text(
        title,
        style: SlowlightTypography.fieldLabel(context),
      );
}
