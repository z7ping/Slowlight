import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/observation_tag.dart';
import '../repositories/observation_tag_repository.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';

class HabitEditorValue {
  final String name;
  final String icon;
  final String color;
  final String frequency;
  final int targetDays;
  final int? systemTagId;
  final String preferredPeriod;
  final int durationMin;
  final bool generateTask;
  final bool showCheckinDialog;
  final String specificTime;
  final Map<String, dynamic> reminderAt;

  const HabitEditorValue({
    required this.name,
    required this.icon,
    required this.color,
    required this.frequency,
    required this.targetDays,
    required this.systemTagId,
    required this.preferredPeriod,
    required this.durationMin,
    required this.generateTask,
    required this.showCheckinDialog,
    required this.specificTime,
    required this.reminderAt,
  });
}

class HabitEditorDialog extends StatefulWidget {
  final Habit? habit;

  const HabitEditorDialog({super.key, this.habit});

  static Future<HabitEditorValue?> show(
    BuildContext context, {
    Habit? habit,
  }) {
    return showDialog<HabitEditorValue>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .45),
      builder: (_) => HabitEditorDialog(habit: habit),
    );
  }

  @override
  State<HabitEditorDialog> createState() => _HabitEditorDialogState();
}

class _HabitEditorDialogState extends State<HabitEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _targetDays;
  late final TextEditingController _duration;
  List<ObservationTag> _tags = const [];
  bool _loadingTags = true;
  late String _icon;
  late String _color;
  late String _frequency;
  int? _systemTagId;
  late String _preferredPeriod;
  late bool _generateTask;
  late bool _showCheckinDialog;
  TimeOfDay? _specificTime;
  TimeOfDay? _reminder;

  static const _templates = <Map<String, String>>[
    {'name': '早起', 'icon': '🌅', 'color': '#fa8c16'},
    {'name': '喝水', 'icon': '💧', 'color': '#13c2c2'},
    {'name': '运动', 'icon': '💪', 'color': '#52c41a'},
    {'name': '阅读', 'icon': '📚', 'color': '#1890ff'},
    {'name': '冥想', 'icon': '🧘', 'color': '#722ed1'},
    {'name': '早睡', 'icon': '💤', 'color': '#2f54eb'},
  ];

  static const _icons = [
    '✅', '💪', '📚', '🏃', '🧘', '💧', '🍎', '💤', '📝', '🎯', '✍️', '🌍',
    '🌅',
  ];
  static const _colors = [
    '#52c41a',
    '#1890ff',
    '#722ed1',
    '#eb2f96',
    '#fa8c16',
    '#13c2c2',
    '#f5222d',
    '#2f54eb',
  ];

  @override
  void initState() {
    super.initState();
    final habit = widget.habit;
    _name = TextEditingController(text: habit?.name ?? '');
    _targetDays = TextEditingController(
      text: (habit?.targetDays ?? 0).toString(),
    );
    _duration = TextEditingController(
      text: (habit?.durationMin ?? 0).toString(),
    );
    _icon = habit?.icon ?? '✅';
    _color = habit?.color ?? '#52c41a';
    _frequency = habit?.frequency ?? 'daily';
    _systemTagId = habit?.systemTagId;
    _preferredPeriod = habit?.preferredPeriod ?? '';
    _specificTime = _parseTime(habit?.specificTime ?? '');
    _generateTask = habit?.generateTask ?? false;
    _showCheckinDialog = habit?.showCheckinDialog ?? false;

    final reminderAt = habit?.reminderAt ?? const <String, dynamic>{};
    final hour = reminderAt['hour'] as int?;
    final minute = reminderAt['minute'] as int?;
    final enabled = reminderAt['enabled'];
    if (enabled != false &&
        hour != null &&
        minute != null &&
        hour >= 0 &&
        hour <= 23 &&
        minute >= 0 &&
        minute <= 59) {
      _reminder = TimeOfDay(hour: hour, minute: minute);
    }
    _loadTags();
  }

  @override
  void dispose() {
    _name.dispose();
    _targetDays.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    try {
      final tags = await ObservationTagRepository().getAll();
      if (!mounted) return;
      setState(() {
        _tags = tags;
        if (_systemTagId != null &&
            !tags.any((tag) => tag.id == _systemTagId)) {
          _systemTagId = null;
        }
        _loadingTags = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _systemTagId = null;
        _loadingTags = false;
      });
    }
  }

  void _applyTemplate(Map<String, String> template) {
    setState(() {
      _name.text = template['name'] ?? '';
      _icon = template['icon'] ?? '✅';
      _color = template['color'] ?? '#52c41a';
      _frequency = 'daily';
    });
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      HabitEditorValue(
        name: name,
        icon: _icon,
        color: _color,
        frequency: _frequency,
        targetDays: int.tryParse(_targetDays.text.trim()) ?? 0,
        systemTagId: _systemTagId,
        preferredPeriod: _preferredPeriod,
        durationMin: int.tryParse(_duration.text.trim()) ?? 0,
        generateTask: _generateTask,
        showCheckinDialog: _showCheckinDialog,
        specificTime:
            _specificTime == null ? '' : _formatTime(_specificTime!),
        reminderAt: _reminder == null
            ? const <String, dynamic>{'enabled': false}
            : {
                'enabled': true,
                'hour': _reminder!.hour,
                'minute': _reminder!.minute,
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: mobile ? 12 : 24,
        vertical: 24,
      ),
      backgroundColor: fxSurface(context),
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: fxBorder(context)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: fxDivider(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.habit == null ? '添加习惯' : '编辑习惯',
                          style: SlowlightTypography.cardTitle(context).copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: fxDivider(context)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.habit == null) ...[
                      Text(
                        '快速添加',
                        style: SlowlightTypography.caption(context).copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _templates.map((template) {
                          final name = template['name']!;
                          final icon = template['icon']!;
                          final selected =
                              _name.text.trim() == name && _icon == icon;
                          return ChoiceChip(
                            label: Text('$icon $name'),
                            labelStyle: const TextStyle(fontSize: AppTheme.textXs),
                            showCheckmark: false,
                            selected: selected,
                            selectedColor:
                                activePalette.accent.withValues(alpha: .12),
                            side: BorderSide(
                              color: selected
                                  ? activePalette.accent
                                  : fxBorder(context),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                            onSelected: (_) => _applyTemplate(template),
                          );
                        }).toList(growable: false),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _name,
                      autofocus: widget.habit == null,
                      onChanged: (_) => setState(() {}),
                      style: SlowlightTypography.body(context),
                      decoration: const InputDecoration(
                        hintText: '习惯名称',
                        labelText: null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _fieldLabel('频率'),
                    FxSegmented(
                      labels: const ['每天', '每周', '每月'],
                      selectedIndex: switch (_frequency) {
                        'weekly' => 1,
                        'monthly' => 2,
                        _ => 0,
                      },
                      onChanged: (index) => setState(() {
                        _frequency = const ['daily', 'weekly', 'monthly'][index];
                      }),
                      backgroundColor: fxSubtleSurface(context),
                      selectedColor: fxSurface(context),
                      borderRadius: AppTheme.radiusMd,
                    ),
                    const SizedBox(height: 16),
                    _fieldLabel('图标'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _icons
                          .map(
                            (icon) => ChoiceChip(
                              label: Text(icon),
                              showCheckmark: false,
                              selected: _icon == icon,
                              selectedColor:
                                  activePalette.accent.withValues(alpha: .12),
                              side: BorderSide(
                                color: _icon == icon
                                    ? activePalette.accent
                                    : fxBorder(context),
                              ),
                              onSelected: (_) => setState(() => _icon = icon),
                            ),
                          )
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 16),
                    _fieldLabel('颜色'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: _colors.map((color) {
                        final parsed = _parseColor(color);
                        return InkWell(
                          onTap: () => setState(() => _color = color),
                          borderRadius: BorderRadius.circular(22),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: parsed,
                                  shape: BoxShape.circle,
                                  border: _color == color
                                      ? Border.all(
                                          color: theme.colorScheme.onSurface,
                                          width: 2,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(growable: false),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _targetDays,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '目标天数',
                              helperText: '0 表示不设目标',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _duration,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '预期时长（分钟）',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _preferredPeriod,
                      decoration: const InputDecoration(labelText: '偏好时段'),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('不限')),
                        DropdownMenuItem(value: 'morning', child: Text('早晨')),
                        DropdownMenuItem(value: 'afternoon', child: Text('下午')),
                        DropdownMenuItem(value: 'evening', child: Text('傍晚')),
                        DropdownMenuItem(value: 'night', child: Text('晚间')),
                      ],
                      onChanged: (value) =>
                          setState(() => _preferredPeriod = value ?? ''),
                    ),
                    _timeRow(
                      title: '计划执行时间',
                      value: _specificTime,
                      onChanged: (value) => setState(() => _specificTime = value),
                    ),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<int?>(
                      value: _loadingTags ? null : _systemTagId,
                      decoration: const InputDecoration(labelText: '观察标签'),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('无')),
                        ..._tags.map(
                          (tag) => DropdownMenuItem<int?>(
                            value: tag.id,
                            child: Text('${tag.icon} ${tag.name}'),
                          ),
                        ),
                      ],
                      onChanged: _loadingTags
                          ? null
                          : (value) => setState(() => _systemTagId = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('打卡时记录详情'),
                      subtitle: const Text('可填写时长、时段和备注'),
                      value: _showCheckinDialog,
                      onChanged: (value) =>
                          setState(() => _showCheckinDialog = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('自动生成任务'),
                      value: _generateTask,
                      onChanged: (value) =>
                          setState(() => _generateTask = value),
                    ),
                    _timeRow(
                      title: '提醒时间',
                      value: _reminder,
                      onChanged: (value) => setState(() => _reminder = value),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: fxDivider(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  FxButton(
                    label: '取消',
                    variant: FxButtonVariant.outline,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FxButton(
                      label: widget.habit == null ? '创建习惯' : '保存',
                      onPressed: _submit,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: SlowlightTypography.caption(context).copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );

  Widget _timeRow({
    required String title,
    required TimeOfDay? value,
    required ValueChanged<TimeOfDay?> onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 48,
      title: Text(title),
      subtitle: Text(value == null ? '未设置' : _formatTime(value)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                tooltip: '清除',
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.close, size: 18),
              ),
            ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              tooltip: '选择时间',
              onPressed: () async {
                final picked = await showFxTimePicker(
                  context: context,
                  initialTime: value ?? const TimeOfDay(hour: 8, minute: 0),
                );
                if (picked != null && mounted) onChanged(picked);
              },
              icon: const Icon(Icons.schedule),
            ),
          ),
        ],
      ),
    );
  }

  TimeOfDay? _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTime(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  Color _parseColor(String value) {
    final hex = value.replaceFirst('#', '');
    final parsed = int.tryParse('FF$hex', radix: 16) ?? 0xFF52C41A;
    return Color(parsed);
  }
}
