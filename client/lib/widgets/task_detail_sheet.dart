import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/task.dart';
import '../models/todo_list.dart';
import '../services/api_service.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import 'high_fidelity/high_fidelity_ui.dart';

/// 任务详情：桌面右侧面板，窄屏底部弹层。
class TaskDetailSheet extends StatefulWidget {
  final Task task;
  final List<TodoList> lists;
  final VoidCallback onChanged;
  final bool sidePanel;

  const TaskDetailSheet({
    super.key,
    required this.task,
    required this.lists,
    required this.onChanged,
    this.sidePanel = false,
  });

  static Future<void> show(
    BuildContext context, {
    required Task task,
    required List<TodoList> lists,
    required VoidCallback onChanged,
  }) {
    final desktop = MediaQuery.sizeOf(context).width >= 600;
    if (desktop) {
      return showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: '关闭任务详情',
        barrierColor: Colors.black.withValues(alpha: .28),
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (dialogContext, _, __) => Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: hfSurface(dialogContext),
            elevation: 18,
            shadowColor: Colors.black.withValues(alpha: .18),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(AppTheme.radiusXl),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 420,
              height: MediaQuery.sizeOf(dialogContext).height,
              child: SafeArea(
                child: TaskDetailSheet(
                  task: task,
                  lists: lists,
                  onChanged: onChanged,
                  sidePanel: true,
                ),
              ),
            ),
          ),
        ),
        transitionBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
      );
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .45),
      builder: (sheetContext) => Padding(
        // 键盘避让：备注/标题输入时 sheet 随 viewInsets 上移
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 560,
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(sheetContext).width * .94,
              maxHeight: MediaQuery.sizeOf(sheetContext).height * .90,
            ),
            decoration: BoxDecoration(
              color: hfSurface(sheetContext),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            clipBehavior: Clip.antiAlias,
            child: TaskDetailSheet(
              task: task,
              lists: lists,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<TaskDetailSheet> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late int? _listId;
  late String _priority;
  late DateTime? _dueDate;
  late TimeOfDay? _dueTime;
  late String _repeatType;
  late int _repeatInterval;
  late Set<int> _weekdays;
  late DateTime? _reminderAt;
  late int _reminderAdvanceMinutes;
  late int? _systemTagId;
  List<Map<String, dynamic>> _systemTags = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _title = TextEditingController(text: task.title);
    _description = TextEditingController(text: task.description ?? '');
    _listId = task.listId;
    _priority = task.priority;
    _dueDate = task.dueDate;
    _dueTime = _parseTime(task.dueTime);
    _repeatType = task.repeatType;
    _repeatInterval = task.repeatInterval;
    _weekdays = task.repeatDays.isEmpty
        ? <int>{}
        : task.repeatDays
            .split(',')
            .map(int.tryParse)
            .whereType<int>()
            .toSet();
    _reminderAt = task.reminderAt;
    _reminderAdvanceMinutes = task.reminderAdvanceMinutes;
    _systemTagId = task.systemTagId;
    _loadSystemTags();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadSystemTags() async {
    try {
      final tags = await ApiService.getSystemTags();
      if (mounted) setState(() => _systemTags = tags);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        Divider(height: 1, color: hfDivider(context)),
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: _form(),
          ),
        ),
        Divider(height: 1, color: hfDivider(context)),
        _footer(),
      ],
    );
  }

  Widget _header() {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, widget.sidePanel ? 10 : 12, 10, 8),
      child: Column(
        children: [
          if (!widget.sidePanel) ...[
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: hfDivider(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              const Expanded(
                child: Text(
                  '任务详情',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (widget.task.isCompleted)
                const HfChip('已完成', accent: true),
              const SizedBox(width: 4),
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  tooltip: '关闭',
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: Icon(
                    LucideIcons.x,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _title,
          autofocus: false,
          enabled: !_saving,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          decoration: const InputDecoration(hintText: '任务标题'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _description,
          enabled: !_saving,
          minLines: 2,
          maxLines: 4,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(hintText: '描述（可选）'),
        ),
        const SizedBox(height: 14),
        _fieldLabel('清单'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: widget.lists.map((list) {
            final selected = _listId == list.id;
            return ChoiceChip(
              label: Text('${list.icon} ${list.name}'),
              labelStyle: const TextStyle(fontSize: AppTheme.textXs),
              showCheckmark: false,
              selected: selected,
              selectedColor: activePalette.accent.withValues(alpha: .12),
              onSelected: _saving ? null : (_) => setState(() => _listId = list.id),
            );
          }).toList(growable: false),
        ),
        const SizedBox(height: 14),
        _fieldLabel('优先级'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _priorityChip('urgent_important', '🔴 高'),
            _priorityChip('important', '🔵 中'),
            _priorityChip('urgent', '⚪ 低'),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _pickerField(
                label: '到期日期',
                value: _dueDate == null ? '未设置' : _dateLabel(_dueDate!),
                icon: LucideIcons.calendarDays,
                onTap: _pickDate,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _pickerField(
                label: '时间',
                value: _dueTime == null ? '未设置' : _timeLabel(_dueTime!),
                icon: LucideIcons.clock3,
                onTap: _pickTime,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _fieldLabel('重复'),
        DropdownButtonFormField<String>(
          value: _repeatType,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('不重复')),
            DropdownMenuItem(value: 'daily', child: Text('每天')),
            DropdownMenuItem(value: 'weekly', child: Text('每周')),
            DropdownMenuItem(value: 'monthly', child: Text('每月')),
          ],
          onChanged: _saving
              ? null
              : (value) => setState(() {
                    _repeatType = value ?? 'none';
                    if (_repeatType != 'weekly') _weekdays.clear();
                  }),
        ),
        if (_repeatType == 'weekly') ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(7, (index) {
              final day = index + 1;
              const labels = ['一', '二', '三', '四', '五', '六', '日'];
              final selected = _weekdays.contains(day);
              return ChoiceChip(
                label: Text(labels[index]),
                labelStyle: const TextStyle(fontSize: AppTheme.textXs),
                showCheckmark: false,
                selected: selected,
                selectedColor: activePalette.accent.withValues(alpha: .12),
                onSelected: _saving
                    ? null
                    : (_) => setState(() {
                          selected ? _weekdays.remove(day) : _weekdays.add(day);
                        }),
              );
            }),
          ),
        ],
        const SizedBox(height: 14),
        _pickerField(
          label: '提醒',
          value: _reminderAt == null
              ? '不提醒'
              : '${_dateLabel(_reminderAt!)} ${_timeLabel(TimeOfDay.fromDateTime(_reminderAt!))}',
          icon: LucideIcons.bell,
          onTap: _pickReminder,
        ),
        if (_systemTags.isNotEmpty) ...[
          const SizedBox(height: 14),
          _fieldLabel('观察标签'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _systemTags.map((tag) {
              final id = tag['id'] as int?;
              if (id == null) return const SizedBox.shrink();
              final selected = id == _systemTagId;
              return ChoiceChip(
                label: Text('${tag['icon'] ?? '🏷️'} ${tag['name'] ?? ''}'),
                labelStyle: const TextStyle(fontSize: AppTheme.textXs),
                showCheckmark: false,
                selected: selected,
                selectedColor: activePalette.accent.withValues(alpha: .12),
                onSelected: _saving
                    ? null
                    : (_) => setState(() => _systemTagId = selected ? null : id),
              );
            }).toList(growable: false),
          ),
        ],
      ],
    );
  }

  Widget _priorityChip(String value, String label) {
    final selected = _priority == value;
    return ChoiceChip(
      label: Text(label),
      labelStyle: const TextStyle(fontSize: AppTheme.textXs),
      showCheckmark: false,
      selected: selected,
      selectedColor: activePalette.accent.withValues(alpha: .12),
      onSelected: _saving
          ? null
          : (on) => setState(() => _priority = on ? value : 'none'),
    );
  }

  Widget _pickerField({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        InkWell(
          onTap: _saving ? null : onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: hfBorder(context)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(value, style: const TextStyle(fontSize: 12.5)),
                ),
                Icon(
                  icon,
                  size: 15,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTheme.textXs,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _footer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
        child: Row(
          children: [
            FxButton(
              label: '删除',
              icon: LucideIcons.trash2,
              variant: FxButtonVariant.ghost,
              onPressed: _saving ? null : _delete,
            ),
            const Spacer(),
            FxButton(
              label: _saving ? '保存中…' : '保存修改',
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final result = await showFxDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (result != null && mounted) setState(() => _dueDate = result);
  }

  Future<void> _pickTime() async {
    final result = await showFxTimePicker(
      context: context,
      initialTime: _dueTime ?? TimeOfDay.now(),
    );
    if (result != null && mounted) setState(() => _dueTime = result);
  }

  Future<void> _pickReminder() async {
    final date = await showFxDatePicker(
      context: context,
      initialDate: _reminderAt ?? _dueDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final time = await showFxTimePicker(
      context: context,
      initialTime: _reminderAt == null
          ? (_dueTime ?? TimeOfDay.now())
          : TimeOfDay.fromDateTime(_reminderAt!),
    );
    if (time == null || !mounted) return;
    setState(() {
      _reminderAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _reminderAdvanceMinutes = 0;
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final listId = _listId ?? (widget.lists.isEmpty ? null : widget.lists.first.id);
    if (title.isEmpty || listId == null) return;
    setState(() => _saving = true);
    try {
      await DataService().updateTask(
        localId: widget.task.id,
        serverId: null,
        listId: listId,
        title: title,
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        priority: _priority,
        dueDate: _dueDate,
        dueTime: _dueTime == null ? null : _timeLabel(_dueTime!),
        repeatType: _repeatType,
        repeatInterval: _repeatInterval,
        repeatDays: _weekdays.isEmpty
            ? ''
            : (_weekdays.toList()..sort()).join(','),
        reminderAt: _reminderAt,
        reminderAdvanceMinutes: _reminderAdvanceMinutes,
        tagIds: widget.task.tags.map((tag) => tag.id).toList(),
        systemTagId: _systemTagId,
        taskType: widget.task.taskType,
        moodBefore: widget.task.moodBefore,
        moodAfter: widget.task.moodAfter,
        isMilestone: widget.task.isMilestone,
        relatedQuestId: widget.task.relatedQuestId,
        obsidianLink: widget.task.obsidianLink,
        outputLevel: widget.task.outputLevel,
      );
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  Future<void> _delete() async {
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '删除任务',
      content: '确定删除「${widget.task.title}」吗？',
      confirmText: '删除',
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final task = widget.task;
    try {
      await DataService().deleteTask(task.id, null);
      widget.onChanged();
      if (!mounted) return;
      Navigator.pop(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          content: Text('已删除「${task.title}」'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () async {
              try {
                await DataService().createTask(
                  listId: task.listId,
                  title: task.title,
                  description: task.description,
                  priority: task.priority,
                  dueDate: task.dueDate,
                  dueTime: task.dueTime,
                  repeatType: task.repeatType,
                  repeatInterval: task.repeatInterval,
                  repeatDays: task.repeatDays,
                  reminderAt: task.reminderAt,
                  reminderAdvanceMinutes: task.reminderAdvanceMinutes,
                  tagIds: task.tags.map((tag) => tag.id).toList(),
                  systemTagId: task.systemTagId,
                  taskType: task.taskType,
                  moodBefore: task.moodBefore,
                  moodAfter: task.moodAfter,
                  isMilestone: task.isMilestone,
                  relatedQuestId: task.relatedQuestId,
                  obsidianLink: task.obsidianLink,
                  outputLevel: task.outputLevel,
                );
                widget.onChanged();
              } catch (_) {}
            },
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  TimeOfDay? _parseTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _timeLabel(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  String _dateLabel(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
