import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/habit_schedule_rule.dart';
import '../models/observation_tag.dart';
import '../models/tag.dart';
import '../repositories/tag_links_repository.dart';
import '../repositories/observation_tag_repository.dart';
import '../ui/fx.dart';
import 'tag_choice_field.dart';
import 'tag_picker.dart';

class HabitEditorValue {
  final String name;
  final String icon;
  final String color;
  final String frequency;
  final Map<String, dynamic> scheduleRule;
  final String recordType;
  final String recordUnit;
  final String recordTimeLabel;
  final bool allowMultiplePerDay;
  final String goalPeriod;
  final String goalMetric;
  final int goalValue;
  final int targetDays;
  final int? systemTagId;
  final List<int>? tagIds;
  final List<Tag> selectedTags;
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
    this.scheduleRule = const {},
    this.recordType = 'legacy',
    this.recordUnit = '次',
    this.recordTimeLabel = '',
    this.allowMultiplePerDay = false,
    this.goalPeriod = 'none',
    this.goalMetric = 'events',
    this.goalValue = 0,
    required this.targetDays,
    required this.systemTagId,
    this.tagIds,
    this.selectedTags = const [],
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
  final Future<void> Function(HabitEditorValue)? onSubmit;
  final HabitEditorValue? initialValue;
  final ValueChanged<HabitEditorValue>? onUnconfirmed;

  const HabitEditorDialog(
      {super.key,
      this.habit,
      this.onSubmit,
      this.initialValue,
      this.onUnconfirmed});

  static Future<HabitEditorValue?> show(BuildContext context,
      {Habit? habit,
      Future<void> Function(HabitEditorValue)? onSubmit,
      HabitEditorValue? initialValue,
      ValueChanged<HabitEditorValue>? onUnconfirmed}) {
    Widget editor(BuildContext _) => HabitEditorDialog(
          habit: habit,
          onSubmit: onSubmit,
          initialValue: initialValue,
          onUnconfirmed: onUnconfirmed,
        );
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      // One sheet surface, preserving the existing explicit cancellation and
      // in-flight-save protection instead of adding a nested dialog.
      return FxSheet.show<HabitEditorValue>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        draggable: false,
        showCloseButton: false,
        padding: EdgeInsets.zero,
        backgroundColor: fxSurface(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SlowlightRadius.sheet),
          ),
        ),
        builder: editor,
      );
    }
    return FxDialog.raw<HabitEditorValue>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .45),
      builder: editor,
    );
  }

  @override
  State<HabitEditorDialog> createState() => _HabitEditorDialogState();
}

class _HabitEditorDialogState extends State<HabitEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _targetDays;
  late final TextEditingController _duration;
  late final TextEditingController _recordUnit;
  late final TextEditingController _recordTimeLabel;
  late final TextEditingController _goalValue;
  late bool _allowMultiplePerDay;
  late String _goalPeriod;
  late String _goalMetric;
  List<ObservationTag> _tags = const [];
  bool _loadingTags = true;
  String? _validationError;
  bool _submitting = false;
  bool _resultUnknown = false;
  bool _canonicalTagsReady = false;
  List<Tag> _selectedTags = const [];
  late String _icon;
  late String _color;
  late String _frequency;
  final Map<String, String> _modeUnits = {'interval':'day','specific':'week','goal':'week'};
  final Map<String, String> _modeEvery = {'interval':'1','specific':'1','goal':'1'};
  late String _mode;
  late String _unit;
  late String _hourMode;
  late String _reminderMode;
  late bool _monthLast;
  late bool _sameDayMultiple;
  late List<int> _weekdays;
  late List<int> _monthDays;
  late TimeOfDay _windowStart;
  late TimeOfDay _windowEnd;
  late final TextEditingController _every;
  late final TextEditingController _targetCount;
  late final TextEditingController _anchorDate;
  late String _recordType;
  int? _systemTagId;
  late String _preferredPeriod;
  late bool _generateTask;
  late bool _showCheckinDialog;
  TimeOfDay? _specificTime;
  TimeOfDay? _reminder;

  static const _templates = <Map<String, String>>[
    {'name': '每2小时喝水', 'icon': '💧', 'color': '#13c2c2', 'mode': 'interval', 'unit': 'hour', 'every': '2'},
    {'name': '每周三次', 'icon': '🏃', 'color': '#52c41a', 'mode': 'goal', 'unit': 'week', 'every': '1', 'target': '3'},
    {'name': '周一三五', 'icon': '📚', 'color': '#1890ff', 'mode': 'specific', 'unit': 'week', 'every': '1'},
    {
      'name': '早起',
      'icon': '🌅',
      'color': '#fa8c16',
      'record_type': 'check',
      'record_time_label': '起床时间'
    },
    {
      'name': '喝水',
      'icon': '💧',
      'color': '#13c2c2',
      'record_type': 'count',
      'record_unit': '杯',
      'allow_multiple_per_day': 'true',
      'goal_period': 'day',
      'goal_metric': 'count',
      'goal_value': '8'
    },
    {'name': '运动', 'icon': '💪', 'color': '#52c41a'},
    {'name': '阅读', 'icon': '📚', 'color': '#1890ff', 'record_type': 'duration'},
    {'name': '冥想', 'icon': '🧘', 'color': '#722ed1'},
    {'name': '早睡', 'icon': '💤', 'color': '#2f54eb'},
  ];

  static const _icons = [
    '✅',
    '💪',
    '📚',
    '🏃',
    '🧘',
    '💧',
    '🍎',
    '💤',
    '📝',
    '🎯',
    '✍️',
    '🌍',
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
    _recordType = habit?.recordType ?? 'check';
    _recordUnit = TextEditingController(text: habit?.recordUnit ?? '次');
    _recordTimeLabel =
        TextEditingController(text: habit?.recordTimeLabel ?? '');
    _allowMultiplePerDay = habit?.allowMultiplePerDay ?? false;
    _goalPeriod = habit?.goalPeriod ?? 'none';
    _goalMetric = habit?.goalMetric ?? 'events';
    _goalValue =
        TextEditingController(text: (habit?.goalValue ?? 0).toString());
    final rule = HabitScheduleRule.fromJson(
      habit?.scheduleRule ?? const {}, legacyFrequency: _frequency,
    );
    _mode = rule.kind;
    _unit = rule.unit;
    _modeUnits[_mode] = _unit;
    _modeEvery[_mode] = rule.every.toString();
    _hourMode = rule.hourMode;
    _reminderMode = rule.reminderMode;
    _monthLast = rule.lastDay;
    _sameDayMultiple = rule.sameDayMultiple;
    _weekdays = List.of(rule.weekdays);
    _monthDays = List.of(rule.monthDays);
    _every = TextEditingController(text: rule.every.toString());
    _targetCount = TextEditingController(text: rule.targetCount.toString());
    _anchorDate = TextEditingController(text: rule.anchorDate);
    _windowStart = _parseTime(rule.windowStart) ?? const TimeOfDay(hour: 8, minute: 0);
    _windowEnd = _parseTime(rule.windowEnd) ?? const TimeOfDay(hour: 22, minute: 0);
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
    _loadCanonicalTags();
    final draft = widget.initialValue;
    if (draft != null) {
      _name.text = draft.name;
      _targetDays.text = '${draft.targetDays}';
      _duration.text = '${draft.durationMin}';
      _recordUnit.text = draft.recordUnit;
      _recordTimeLabel.text = draft.recordTimeLabel;
      _goalValue.text = '${draft.goalValue}';
      _icon = draft.icon;
      _color = draft.color;
      _frequency = draft.frequency;
      _recordType = draft.recordType;
      _allowMultiplePerDay = draft.allowMultiplePerDay;
      _goalPeriod = draft.goalPeriod;
      _goalMetric = draft.goalMetric;
      _systemTagId = draft.systemTagId;
      _preferredPeriod = draft.preferredPeriod;
      _specificTime = _parseTime(draft.specificTime);
      _generateTask = draft.generateTask;
      _showCheckinDialog = draft.showCheckinDialog;
      _reminder = draft.reminderAt['enabled'] == true
          ? TimeOfDay(
              hour: draft.reminderAt['hour'] as int,
              minute: draft.reminderAt['minute'] as int)
          : null;
      _resultUnknown = true;
      _validationError = '已恢复上次未确认的草稿。请核对列表；确认未保存后再允许重新保存。';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _targetDays.dispose();
    _duration.dispose();
    _recordUnit.dispose();
    _recordTimeLabel.dispose();
    _goalValue.dispose();
    _every.dispose();
    _targetCount.dispose();
    _anchorDate.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    try {
      final tags = await ObservationTagRepository().getAll();
      if (!mounted) return;
      setState(() {
        _tags = tags;
        _loadingTags = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        // 标签读取失败不应清空已有的关联，避免保存其他字段时丢失数据。
        _loadingTags = false;
      });
    }
  }

  Future<void> _loadCanonicalTags() async {
    if (widget.initialValue case final draft?) {
      _selectedTags = List<Tag>.from(draft.selectedTags);
      _canonicalTagsReady = draft.tagIds != null;
      return;
    }
    final habit = widget.habit;
    if (habit == null) {
      if (mounted) setState(() => _canonicalTagsReady = true);
      return;
    }
    try {
      final tags =
          await TagLinksRepository().getFor(TagLinkedEntity.habit, habit.id);
      if (!mounted) return;
      setState(() {
        _selectedTags = tags;
        _canonicalTagsReady = true;
      });
    } catch (_) {
      // 编辑其他字段时不能把加载失败解释成“用户清空了标签”。
      // 当前模式下不提供多选编辑，提交时保持现有关联不动。
    }
  }

  void _applyTemplate(Map<String, String> template) {
    setState(() {
      _name.text = template['name'] ?? '';
      _icon = template['icon'] ?? '✅';
      _color = template['color'] ?? '#52c41a';
      _frequency = 'daily';
      _mode = template['mode'] ?? 'interval';
      _unit = template['unit'] ?? 'day';
      _every.text = template['every'] ?? '1';
      _targetCount.text = template['target'] ?? '3';
      _modeUnits[_mode] = _unit;
      _modeEvery[_mode] = _every.text;
      if (_mode == 'specific') _weekdays = [1, 3, 5];
      _recordType = template['record_type'] ?? 'check';
      _recordTimeLabel.text = template['record_time_label'] ?? '';
      _allowMultiplePerDay = template['allow_multiple_per_day'] == 'true';
      _goalPeriod = template['goal_period'] ?? 'none';
      _goalMetric = template['goal_metric'] ?? 'events';
      _goalValue.text = template['goal_value'] ?? '0';
      _recordUnit.text = template['record_unit'] ?? '次';
    });
  }

  HabitScheduleRule _currentRule() => HabitScheduleRule(
    kind: _mode, unit: _unit,
    every: int.tryParse(_every.text.trim()) ?? 0,
    anchorDate: _anchorDate.text.trim(),
    anchorTime: _specificTime == null ? '08:00' : _formatTime(_specificTime!),
    hourMode: _hourMode,
    windowStart: _formatTime(_windowStart),
    windowEnd: _formatTime(_windowEnd),
    weekdays: _weekdays, monthDays: _monthDays,
    lastDay: _monthLast,
    targetCount: int.tryParse(_targetCount.text.trim()) ?? 0,
    sameDayMultiple: _sameDayMultiple,
    reminderMode: _reminderMode,
    reminderTime: _reminder == null ? '09:00' : _formatTime(_reminder!),
  );

  Future<void> _submit() async {
    if (_submitting || _resultUnknown) return;
    final name = _name.text.trim();
    final rule = _currentRule();
    final targetText = _targetDays.text.trim();
    final durationText = _duration.text.trim();
    final target = targetText.isEmpty ? 0 : int.tryParse(targetText);
    final duration = durationText.isEmpty ? 0 : int.tryParse(durationText);
    final recordUnit = _recordUnit.text.trim();
    final recordTimeLabel = _recordTimeLabel.text.trim();
    final goalValue = int.tryParse(_goalValue.text.trim());
    String? error;
    if (name.isEmpty) {
      error = '请填写习惯名称';
    } else if (target == null || target < 0) {
      error = '目标天数必须是 0 或正整数';
    } else if (recordUnit.isEmpty || recordUnit.length > 20) {
      error = '计数单位应为 1～20 个字符';
    } else if (recordTimeLabel.length > 40) {
      error = '实际时间字段名称不能超过 40 字';
    } else if (duration == null || duration < 0) {
      error = '预期时长必须是 0 或正整数';
    } else if (goalValue == null || goalValue < 0 || goalValue > 100000) {
      error = '周期目标必须是 0～100000';
    } else if (goalValue > 0 && _goalPeriod == 'none') {
      error = '请为目标选择统计周期';
    } else if (goalValue > 0 &&
        ((_goalMetric == 'count' && _recordType != 'count') ||
            (_goalMetric == 'duration' &&
                _recordType != 'duration' &&
                _recordType != 'legacy'))) {
      error = '累计方式与记录类型不匹配';
    }
    if (error == null && rule.validationError != null) {
      error = rule.validationError;
    }
    if (error != null) {
      setState(() => _validationError = error);
      return;
    }
    setState(() => _validationError = null);
    final value = HabitEditorValue(
      name: name,
      icon: _icon,
      color: _color,
      frequency: _mode == 'interval' && rule.every == 1
          ? const {'day': 'daily', 'week': 'weekly', 'month': 'monthly', 'year': 'yearly'}[_unit] ?? 'custom'
          : 'custom',
      scheduleRule: rule.toJson(),
      recordType: _recordType,
      recordUnit: recordUnit,
      recordTimeLabel: recordTimeLabel,
      allowMultiplePerDay: _allowMultiplePerDay,
      goalPeriod: _goalPeriod,
      goalMetric: _goalMetric,
      goalValue: goalValue!,
      targetDays: target!,
      systemTagId: _systemTagId,
      tagIds: _canonicalTagsReady
          ? _selectedTags.map((tag) => tag.id).toList(growable: false)
          : null,
      selectedTags: List<Tag>.unmodifiable(_selectedTags),
      preferredPeriod: _preferredPeriod,
      durationMin: duration!,
      generateTask: _generateTask,
      showCheckinDialog: _showCheckinDialog,
      specificTime: _specificTime == null ? '' : _formatTime(_specificTime!),
      reminderAt: _reminder == null
          ? const <String, dynamic>{'enabled': false}
          : {
              'enabled': true,
              'hour': _reminder!.hour,
              'minute': _reminder!.minute,
            },
    );
    if (widget.onSubmit == null) {
      Navigator.pop(context, value);
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onSubmit!(value);
      if (!mounted) return;
      setState(() => _submitting = false);
      Navigator.pop(context, value);
    } catch (error) {
      if (!mounted) return;
      widget.onUnconfirmed?.call(value);
      setState(() {
        _submitting = false;
        _resultUnknown = true;
        _validationError = '保存结果未确认，输入已保留。请核对习惯列表后再决定是否重新保存：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mobile = theme.platform == TargetPlatform.android ||
        theme.platform == TargetPlatform.iOS;
    final editor = ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: mobile ? MediaQuery.sizeOf(context).height * .88 : 720,
      ),
      child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.habit == null ? '添加习惯' : '编辑习惯',
                    style: SlowlightTypography.cardTitle(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              FxSeparator.horizontal(
                  height: 1,
                  margin: EdgeInsets.zero,
                  color: fxDivider(context)),
              Flexible(
                  child: ExcludeFocus(
                excluding: _submitting,
                child: AbsorbPointer(
                  absorbing: _submitting,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.habit == null) ...[
                          _fieldLabel('快速添加'),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _templates.map((template) {
                              final name = template['name']!;
                              final icon = template['icon']!;
                              final selected =
                                  _name.text.trim() == name && _icon == icon;
                              return FxChoiceChip(
                                label: '$icon $name',
                                selected: selected,
                                onTap: () => _applyTemplate(template),
                              );
                            }).toList(growable: false),
                          ),
                          const SizedBox(height: 14),
                        ],
                        FxInput(
                          controller: _name,
                          autofocus: widget.habit == null && !mobile,
                          onChanged: (_) => setState(() {}),
                          label: '习惯名称',
                          placeholder: '例如：每天阅读 20 分钟',
                        ),
                        const SizedBox(height: 14),
                        _buildScheduleFields(),
                        const SizedBox(height: 14),
                        FxFormField(
                          label: '记录类型',
                          child: FxSegmented(
                            labels: _recordType == 'legacy'
                                ? const ['原有方式', '打卡', '计时', '计数']
                                : const ['打卡', '计时', '计数'],
                            selectedIndex: (_recordType == 'legacy'
                                    ? const [
                                        'legacy',
                                        'check',
                                        'duration',
                                        'count'
                                      ]
                                    : const ['check', 'duration', 'count'])
                                .indexOf(_recordType),
                            onChanged: (index) => setState(() {
                              _recordType = (_recordType == 'legacy'
                                  ? const [
                                      'legacy',
                                      'check',
                                      'duration',
                                      'count'
                                    ]
                                  : const [
                                      'check',
                                      'duration',
                                      'count'
                                    ])[index];
                            }),
                            backgroundColor: fxSubtleSurface(context),
                            selectedColor: fxSurface(context),
                            borderRadius: SlowlightRadius.md,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_recordType == 'count') ...[
                          FxInput(
                              controller: _recordUnit,
                              onChanged: (_) => setState(() {}),
                              label: '计数单位',
                              placeholder: '例如：次、杯、页'),
                          const SizedBox(height: 12),
                        ],
                        if (_recordType == 'legacy') ...[
                          Text('按时长与时段记录；更改方式不会删除已有记录。',
                              style: SlowlightTypography.secondary(context)),
                          const SizedBox(height: SlowlightSpacing.xl),
                        ],
                        if (_canonicalTagsReady)
                          TagPicker(
                            selectedTags: _selectedTags,
                            onChanged: (tags) =>
                                setState(() => _selectedTags = tags),
                          )
                        else
                          Text(
                            '多标签暂不可编辑，原有关联会保留',
                            style: SlowlightTypography.secondary(context),
                          ),
                        const SizedBox(height: SlowlightSpacing.xl),
                        _settingsGroup(
                            'record', '记录与目标', _recordSettingsSummary, [
                          FxInput(
                            controller: _recordTimeLabel,
                            label: '记录实际时间（选填）',
                            placeholder: '如起床时间；留空则不询问具体时间',
                          ),
                          const SizedBox(height: 14),
                          FxSwitch(
                            label: '允许一天多次记录',
                            description: '每次新增独立记录，支持逐条撤销',
                            value: _allowMultiplePerDay,
                            onChanged: (value) =>
                                setState(() => _allowMultiplePerDay = value),
                          ),
                          const SizedBox(height: 12),
                          FxResponsiveFormGrid(
                            minColumnWidth: 180,
                            children: [
                              FxFormField(
                                label: '累计周期',
                                child: FxSelect<String>(
                                  value: _goalPeriod,
                                  options: const [
                                    FxSelectOption(
                                        value: 'none', label: '不设周期目标'),
                                    FxSelectOption(value: 'day', label: '每天累计'),
                                    FxSelectOption(
                                        value: 'week', label: '每周累计'),
                                    FxSelectOption(
                                        value: 'month', label: '每月累计'),
                                  ],
                                  onChanged: (value) => setState(
                                      () => _goalPeriod = value ?? 'none'),
                                ),
                              ),
                              FxFormField(
                                label: '累计方式',
                                child: FxSelect<String>(
                                  value: _goalMetric,
                                  options: const [
                                    FxSelectOption(
                                        value: 'events', label: '记录次数'),
                                    FxSelectOption(
                                        value: 'count', label: '累计数量'),
                                    FxSelectOption(
                                        value: 'duration', label: '累计分钟'),
                                  ],
                                  onChanged: (value) => setState(
                                      () => _goalMetric = value ?? 'events'),
                                ),
                              ),
                              FxInput(
                                  controller: _goalValue,
                                  onChanged: (_) => setState(() {}),
                                  keyboardType: TextInputType.number,
                                  label: '周期目标数值',
                                  placeholder: '0 表示不设目标'),
                            ],
                          ),
                          const SizedBox(height: 14),
                          FxResponsiveFormGrid(
                            minColumnWidth: 260,
                            children: [
                              FxInput(
                                controller: _targetDays,
                                keyboardType: TextInputType.number,
                                label: '目标天数',
                                placeholder: '0 表示不设目标',
                              ),
                              if (_recordType == 'legacy' ||
                                  _recordType == 'duration')
                                FxInput(
                                  controller: _duration,
                                  keyboardType: TextInputType.number,
                                  label: '预期时长（分钟）',
                                  placeholder: '例如 20',
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          FxSwitch(
                            label: '打卡时记录详情',
                            description: '按记录类型填写详情；计数型始终填写实际次数',
                            value: _showCheckinDialog,
                            onChanged: (value) =>
                                setState(() => _showCheckinDialog = value),
                          ),
                        ]),
                        const SizedBox(height: SlowlightSpacing.xl),
                        _settingsGroup('plan', '计划与提醒', _planSettingsSummary, [
                          FxFormField(
                            label: '偏好时段',
                            child: SizedBox(
                              width: double.infinity,
                              child: FxSelect<String>(
                                value: _preferredPeriod,
                                options: const [
                                  FxSelectOption(value: '', label: '不限'),
                                  FxSelectOption(value: 'morning', label: '早晨'),
                                  FxSelectOption(
                                    value: 'afternoon',
                                    label: '下午',
                                  ),
                                  FxSelectOption(value: 'evening', label: '傍晚'),
                                  FxSelectOption(value: 'night', label: '晚间'),
                                ],
                                onChanged: (value) => setState(
                                  () => _preferredPeriod = value ?? '',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: SlowlightSpacing.xl),
                          FxResponsiveFormGrid(
                            minColumnWidth: 260,
                            children: [
                              _timeField(
                                title: '计划执行时间',
                                value: _specificTime,
                                onChanged: (value) =>
                                    setState(() => _specificTime = value),
                              ),
                              _timeField(
                                title: '提醒时间',
                                value: _reminder,
                                onChanged: (value) =>
                                    setState(() => _reminder = value),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          FxSwitch(
                            label: '自动生成任务',
                            value: _generateTask,
                            onChanged: (value) =>
                                setState(() => _generateTask = value),
                          ),
                        ]),
                        const SizedBox(height: SlowlightSpacing.xl),
                        _settingsGroup(
                            'appearance', '图标与更多', '$_icon · 图标、颜色与原有分类', [
                          FxResponsiveFormGrid(
                            minColumnWidth: 260,
                            children: [
                              FxFormField(
                                label: '图标',
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _icons
                                      .map(
                                        (icon) => FxChoiceChip(
                                          label: icon,
                                          selected: _icon == icon,
                                          onTap: () =>
                                              setState(() => _icon = icon),
                                        ),
                                      )
                                      .toList(growable: false),
                                ),
                              ),
                              FxFormField(
                                label: '颜色',
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _colors
                                      .map(
                                          (color) => _colorChoice(color, theme))
                                      .toList(growable: false),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TagChoiceField(
                            label: '原有分类',
                            tags: _tags,
                            selectedTagId: _systemTagId,
                            enabled: !_loadingTags,
                            onChanged: (id) =>
                                setState(() => _systemTagId = id),
                          ),
                          const SizedBox(height: SlowlightSpacing.xs),
                          Text('早期记录的分类与上方多选标签分别保存。',
                              style: SlowlightTypography.caption(context)),
                        ]),
                      ],
                    ),
                  ),
                ),
              )),
              FxSeparator.horizontal(
                  height: 1,
                  margin: EdgeInsets.zero,
                  color: fxDivider(context)),
              if (_validationError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _validationError!,
                      key: const ValueKey('habit-editor-validation-error'),
                      style: SlowlightTypography.secondary(context).copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SlowlightSpacing.xxxl,
                  SlowlightSpacing.xl,
                  SlowlightSpacing.xxxl,
                  SlowlightSpacing.xxxl,
                ),
                child: mobile
                    ? Column(
                        key: const ValueKey('habit-editor-mobile-footer'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_resultUnknown) ...[
                            FxButton(
                              label: '已核对，允许重新保存',
                              expanded: true,
                              variant: FxButtonVariant.outline,
                              onPressed: () => setState(() {
                                _resultUnknown = false;
                                _validationError = null;
                              }),
                            ),
                            const SizedBox(height: SlowlightSpacing.md),
                          ],
                          Row(
                            children: [
                              FxButton(
                                label: '取消',
                                variant: FxButtonVariant.outline,
                                onPressed: _submitting
                                    ? null
                                    : () => Navigator.pop(context),
                              ),
                              const SizedBox(width: SlowlightSpacing.md),
                              Expanded(
                                child: FxButton(
                                  label: _submitting
                                      ? '保存中…'
                                      : widget.habit == null
                                          ? '创建习惯'
                                          : '保存',
                                  expanded: true,
                                  onPressed: _submitting || _resultUnknown
                                      ? null
                                      : _submit,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Wrap(
                        alignment: WrapAlignment.end,
                        spacing: SlowlightSpacing.md,
                        runSpacing: SlowlightSpacing.md,
                        children: [
                          FxButton(
                            label: '取消',
                            variant: FxButtonVariant.outline,
                            onPressed: _submitting
                                ? null
                                : () => Navigator.pop(context),
                          ),
                          if (_resultUnknown)
                            FxButton(
                              label: '已核对，允许重新保存',
                              variant: FxButtonVariant.outline,
                              onPressed: () => setState(() {
                                _resultUnknown = false;
                                _validationError = null;
                              }),
                            ),
                          FxButton(
                            label: _submitting
                                ? '保存中…'
                                : widget.habit == null
                                    ? '创建习惯'
                                    : '保存',
                            onPressed:
                                _submitting || _resultUnknown ? null : _submit,
                          ),
                        ],
                      ),
              ),
            ],
          ),
    );
    return PopScope(
      canPop: !_submitting,
      child: mobile
          ? SafeArea(top: false, child: editor)
          : FxDialogSurface(
              showCloseButton: false,
              padding: EdgeInsets.zero,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              backgroundColor: fxSurface(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SlowlightRadius.xl),
                side: BorderSide(color: fxBorder(context)),
              ),
              child: editor,
            ),
    );
  }

  String get _recordSettingsSummary {
    final period = switch (_goalPeriod) {
      'day' => '每天累计',
      'week' => '每周累计',
      'month' => '每月累计',
      _ => '不设周期目标',
    };
    final metric = switch (_goalMetric) {
      'count' => _recordUnit.text,
      'duration' => '分钟',
      _ => '次',
    };
    return '${_allowMultiplePerDay ? '一天可记多次' : '每天一条'} · '
        '$period${_goalPeriod == 'none' ? '' : ' ${_goalValue.text} $metric'}';
  }

  String get _planSettingsSummary => [
        _specificTime == null ? '未设计划时间' : '计划 ${_formatTime(_specificTime!)}',
        _reminder == null ? '未设提醒' : '提醒 ${_formatTime(_reminder!)}',
        if (_generateTask) '生成任务',
      ].join(' · ');

  Widget _settingsGroup(
          String id, String title, String summary, List<Widget> children) =>
      FxExpansionTile(
        key: ValueKey('habit-editor-settings-$id'),
        title: Text(title),
        subtitle: Text(summary),
        enabled: !_submitting,
        dense: true,
        tilePadding: const EdgeInsets.symmetric(vertical: SlowlightSpacing.xl),
        childrenPadding: const EdgeInsets.only(bottom: SlowlightSpacing.xl),
        children: children,
      );

  Widget _buildScheduleFields() {
    final rule = _currentRule();
    final theme = Theme.of(context);
    final preview = rule.nextAfter(DateTime.now().subtract(const Duration(minutes: 1)), count: 4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FxFormField(
          label: '重复方式',
          child: FxSegmented(
            labels: const ['固定间隔', '指定日期', '周期目标'],
            selectedIndex: const ['interval', 'specific', 'goal'].indexOf(_mode),
            onChanged: (v) => setState(() {
              _modeUnits[_mode] = _unit;
              _modeEvery[_mode] = _every.text;
              _mode = const ['interval', 'specific', 'goal'][v];
              _unit = _modeUnits[_mode] ?? 'week';
              _every.text = _modeEvery[_mode] ?? '1';
              if (_mode == 'goal' && _reminderMode == 'schedule') _reminderMode = 'daily';
            }),
            backgroundColor: fxSubtleSurface(context),
            selectedColor: fxSurface(context),
            borderRadius: SlowlightRadius.md,
          ),
        ),
        const SizedBox(height: 12),
        FxResponsiveFormGrid(
          minColumnWidth: 270,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FxInput(
                  label: _mode == 'goal' ? '每 N 周/月完成目标' : '每 N 小时/天/周/月',
                  controller: _every,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                FxFormField(
                  label: '周期单位',
                  child: _mode == 'interval'
                      ? FxSelect<String>(
                          value: _unit,
                          options: const [
                            FxSelectOption(value: 'hour', label: '小时'),
                            FxSelectOption(value: 'day', label: '天'),
                            FxSelectOption(value: 'week', label: '周'),
                            FxSelectOption(value: 'month', label: '月'),
                            FxSelectOption(value: 'year', label: '年（旧习惯兼容）'),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _unit = v);
                          },
                        )
                      : FxSegmented(
                          labels: const ['周', '月'],
                          selectedIndex: _unit == 'month' ? 1 : 0,
                          onChanged: (i) => setState(() =>
                              _unit = const ['week', 'month'][i]),
                          backgroundColor: fxSubtleSurface(context),
                          selectedColor: fxSurface(context),
                        ),
                ),
                if (_mode == 'interval' && _unit == 'hour') ...[
                  const SizedBox(height: 12),
                  FxFormField(
                    label: '小时循环',
                    child: FxSegmented(
                      labels: const ['连续跨日', '每日时段'],
                      selectedIndex: _hourMode == 'rolling' ? 0 : 1,
                      onChanged: (i) => setState(() => _hourMode = i == 0 ? 'rolling' : 'window'),
                    ),
                  ),
                  if (_hourMode == 'window') ...[
                    const SizedBox(height: 8),
                    FxResponsiveFormGrid(minColumnWidth: 120, children: [
                      _timeField(title: '开始', value: _windowStart,
                        onChanged: (v) { if (v != null) setState(() => _windowStart = v); }),
                      _timeField(title: '结束（可次日）', value: _windowEnd,
                        onChanged: (v) { if (v != null) setState(() => _windowEnd = v); }),
                    ]),
                  ],
                ],
                if (_mode == 'specific') ...[
                  const SizedBox(height: 12),
                  _fieldLabel(_unit == 'week' ? '星期（可多选）' : '每月日期（可多选）'),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (var d = 1; d <= (_unit == 'week' ? 7 : 31); d++)
                      FxChoiceChip(
                        label: _unit == 'week' ? const ['一','二','三','四','五','六','日'][d-1] : '$d',
                        selected: (_unit == 'week' ? _weekdays : _monthDays).contains(d),
                        onTap: () => setState(() {
                          final values = _unit == 'week' ? _weekdays : _monthDays;
                          if (values.contains(d)) {
                            values.remove(d);
                          } else {
                            values.add(d);
                          }
                        }),
                      ),
                  ]),
                  if (_unit == 'month')
                    FxSwitch(label: '每月最后一天', value: _monthLast,
                      onChanged: (v) => setState(() => _monthLast = v)),
                ],
                if (_mode == 'goal') ...[
                  const SizedBox(height: 12),
                  FxInput(
                    controller: _targetCount,
                    label: '周期内完成次数',
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                  FxSwitch(label: '允许同一天计入多次',
                    value: _sameDayMultiple,
                    onChanged: (v) => setState(() => _sameDayMultiple = v)),
                ],
              ],
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: fxSubtleSurface(context),
                borderRadius: BorderRadius.circular(SlowlightRadius.md),
                border: Border.all(color: fxBorder(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fieldLabel('规则预览'),
                  Text(rule.summary, style: SlowlightTypography.cardTitle(context)),
                  const SizedBox(height: 8),
                  if (rule.validationError != null)
                    Text(rule.validationError!, style: SlowlightTypography.secondary(context)
                        .copyWith(color: theme.colorScheme.error))
                  else if (_mode == 'goal')
                    Text('每个周期内自由安排，目标 ' + rule.targetCount.toString() + ' 次',
                        style: SlowlightTypography.secondary(context))
                  else
                    for (final date in preview)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          HabitScheduleRule.dayKey(date) + ' ' +
                          date.hour.toString().padLeft(2, '0') + ':' +
                          date.minute.toString().padLeft(2, '0'),
                          style: SlowlightTypography.secondary(context),
                        ),
                      ),
                  const SizedBox(height: 5),
                  Text('预览不等于实际提醒；漏记不顺延周期。',
                      style: SlowlightTypography.secondary(context)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FxFormField(
          label: '起算日期',
          child: Row(children: [
            Expanded(child: FxInput(controller: _anchorDate,
              placeholder: 'YYYY-MM-DD', keyboardType: TextInputType.datetime,
              onChanged: (_) => setState(() {}))),
            FxIconButton(
              tooltip: '选择起算日期',
              icon: Icons.calendar_today,
              onPressed: () async {
                final value = await showFxDatePicker(
                  context: context,
                  initialDate: _currentRule().anchor ?? DateTime.now(),
                );
                if (value != null && mounted) setState(() =>
                    _anchorDate.text = HabitScheduleRule.dayKey(value));
              },
            ),
          ]),
        ),
        const SizedBox(height: 12),
        _timeField(
          title: '起算／执行时间',
          value: _specificTime,
          onChanged: (v) => setState(() => _specificTime = v),
        ),
        const SizedBox(height: 12),
        FxFormField(
          label: '提醒方式（与频率独立）',
          child: FxSegmented(
            labels: _mode == 'goal'
                ? const ['不提醒', '每天定时'] : const ['不提醒', '按计划', '每天定时'],
            selectedIndex: _mode == 'goal'
                ? (_reminderMode == 'daily' ? 1 : 0)
                : const ['off','schedule','daily'].indexOf(_reminderMode).clamp(0, 2).toInt(),
            onChanged: (v) => setState(() {
              _reminderMode = (_mode == 'goal' ? const ['off','daily'] :
                  const ['off','schedule','daily'])[v];
              if (_reminderMode == 'daily' && _reminder == null) {
                _reminder = const TimeOfDay(hour: 9, minute: 0);
              }
            }),
          ),
        ),
        if (_reminderMode == 'daily') ...[
          const SizedBox(height: 12),
          _timeField(
            title: '每天提醒时间',
            value: _reminder,
            onChanged: (v) => setState(() => _reminder = v),
          ),
        ],
      ],
    );
  }

  Widget _colorChoice(String color, ThemeData theme) {
    final parsed = _parseColor(color);
    final selected = _color == color;
    return FxInkWell(
      onTap: () => setState(() => _color = color),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? theme.colorScheme.onSurface
                : theme.colorScheme.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: parsed, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: SlowlightTypography.fieldLabel(
            context,
          ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );

  Widget _timeField({
    required String title,
    required TimeOfDay? value,
    required ValueChanged<TimeOfDay?> onChanged,
  }) {
    final theme = Theme.of(context);
    return FxFormField(
      label: title,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          color: fxSurface(context),
          borderRadius: BorderRadius.circular(SlowlightRadius.md),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  value == null ? '未设置' : _formatTime(value),
                  style: SlowlightTypography.control(context),
                ),
              ),
            ),
            if (value != null)
              FxIconButton(
                tooltip: '清除',
                onPressed: () => onChanged(null),
                icon: Icons.close,
              ),
            FxIconButton(
              tooltip: '选择时间',
              onPressed: () async {
                final picked = await showFxTimePicker(
                  context: context,
                  initialTime: value ?? const TimeOfDay(hour: 8, minute: 0),
                );
                if (picked != null && mounted) onChanged(picked);
              },
              icon: Icons.schedule,
            ),
          ],
        ),
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
