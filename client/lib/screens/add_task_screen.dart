import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/todo_list.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';

class AddTaskScreen extends StatefulWidget {
  final List<TodoList> lists;
  final int? selectedListId;
  final DateTime? defaultDueDate;
  final String initialTitle;
  final String initialPriority;
  final int? systemTagId;
  final bool isEdit;
  final bool embedded;

  const AddTaskScreen({
    super.key,
    required this.lists,
    this.selectedListId,
    this.defaultDueDate,
    this.initialTitle = '',
    this.initialPriority = 'none',
    this.systemTagId,
    this.isEdit = false,
    this.embedded = false,
  });

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  int? _selectedListId;
  late String _priority;
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  String _repeatType = 'none';
  final Set<int> _selectedWeekdays = {};
  int _reminderAdvanceMinutes = -1;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.initialTitle;
    _selectedListId =
        widget.selectedListId ??
        (widget.lists.isEmpty ? null : widget.lists.first.id);
    _priority = widget.initialPriority;
    _dueDate = widget.defaultDueDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _message('请输入任务标题');
      return;
    }
    final listId = _selectedListId;
    if (listId == null) {
      _message('请先创建一个清单');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final dueTime =
          _dueTime == null
              ? null
              : '${_dueTime!.hour.toString().padLeft(2, '0')}:${_dueTime!.minute.toString().padLeft(2, '0')}';
      final reminderAt = _buildReminderAt();
      final repeatDays =
          _repeatType == 'weekly' && _selectedWeekdays.isNotEmpty
              ? (_selectedWeekdays.toList()..sort()).join(',')
              : '';

      await DataService().createTask(
        listId: listId,
        title: title,
        description:
            _descController.text.trim().isEmpty
                ? null
                : _descController.text.trim(),
        priority: _priority,
        dueDate: _dueDate,
        dueTime: dueTime,
        repeatType: _repeatType,
        repeatInterval: 1,
        repeatDays: repeatDays,
        reminderAt: reminderAt,
        reminderAdvanceMinutes:
            _reminderAdvanceMinutes < 0 ? 0 : _reminderAdvanceMinutes,
        systemTagId: widget.systemTagId,
        taskType: 'daily',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _message('保存失败：$e');
    }
  }

  DateTime? _buildReminderAt() {
    if (_reminderAdvanceMinutes < 0 || _dueDate == null) return null;
    final time = _dueTime ?? const TimeOfDay(hour: 9, minute: 0);
    final due = DateTime(
      _dueDate!.year,
      _dueDate!.month,
      _dueDate!.day,
      time.hour,
      time.minute,
    );
    return due.subtract(Duration(minutes: _reminderAdvanceMinutes));
  }

  void _message(String text) {
    FxNotice.showContent(context, Text(text));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _editorShell(showBack: false);
    return Scaffold(body: SafeArea(child: _editorShell(showBack: true)));
  }

  Widget _editorShell({required bool showBack}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBack)
          FxPageHeader(title: '新建任务', onBack: () => Navigator.maybePop(context))
        else
          _dialogHeader(),
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: _form(),
          ),
        ),
        FxSeparator.horizontal(height: 1, color: fxDivider(context)),
        _footer(),
      ],
    );
  }

  Widget _dialogHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Text(
            '新建任务',
            style: SlowlightTypography.componentDialogTitle(context),
          ),
        ),
        FxSeparator.horizontal(height: 1, color: fxDivider(context)),
      ],
    );
  }

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FxInput(
          controller: _titleController,
          autofocus: true,
          enabled: !_isSaving,
          textInputAction: TextInputAction.next,
          style: SlowlightTypography.emphasizedInput(context),
          placeholder: '任务标题',
        ),
        const SizedBox(height: 8),
        FxInput(
          controller: _descController,
          enabled: !_isSaving,
          minLines: 1,
          maxLines: 3,
          style: SlowlightTypography.componentSecondary(context),
          placeholder: '描述（可选）',
        ),
        const SizedBox(height: 16),
        FxResponsiveFormGrid(
          minColumnWidth: 240,
          children: [
            _listField(),
            _priorityField(),
            _dateField(),
            _timeField(),
            _repeatField(),
            _reminderField(),
          ],
        ),
        if (_repeatType == 'weekly') ...[
          const SizedBox(height: 12),
          _fieldLabel('每周重复'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(7, (index) {
              final day = index + 1;
              const labels = ['一', '二', '三', '四', '五', '六', '日'];
              final selected = _selectedWeekdays.contains(day);
              return _choiceChip(
                labels[index],
                selected: selected,
                onTap:
                    () => setState(() {
                      selected
                          ? _selectedWeekdays.remove(day)
                          : _selectedWeekdays.add(day);
                    }),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _choiceChip(
    String label, {
    required bool selected,
    required VoidCallback onTap,
    Color? selectionColor,
  }) {
    return FxChoiceChip(
      label: label,
      selected: selected,
      selectionColor: selectionColor,
      onTap: _isSaving ? null : onTap,
    );
  }

  Widget _listField() {
    return _field(
      label: '清单',
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: widget.lists
            .map((list) {
              final selected = _selectedListId == list.id;
              return _choiceChip(
                '${list.icon} ${list.name}',
                selected: selected,
                onTap: () => setState(() => _selectedListId = list.id),
              );
            })
            .toList(growable: false),
      ),
    );
  }

  Widget _priorityField() {
    return _field(
      label: '优先级',
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _priorityChip('none', '无', Theme.of(context).colorScheme.onSurface),
          _priorityChip('urgent_important', '高', AppTheme.priorityHigh),
          _priorityChip('important', '中', AppTheme.priorityMedium),
          _priorityChip('urgent', '低', AppTheme.priorityLow),
        ],
      ),
    );
  }

  Widget _priorityChip(String value, String label, Color color) {
    final selected = _priority == value;
    return _choiceChip(
      label,
      selected: selected,
      selectionColor: color,
      onTap: () => setState(() => _priority = value),
    );
  }

  Widget _dateField() {
    return _field(
      label: '到期日期',
      child: _picker(
        text: _dueDate == null ? '未设置' : _dateLabel(_dueDate!),
        icon: LucideIcons.calendarDays,
        onTap: () async {
          final date = await showFxDatePicker(
            context: context,
            initialDate: _dueDate ?? DateTime.now(),
            firstDate: DateTime.now().subtract(const Duration(days: 365)),
            lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
          );
          if (date != null && mounted) setState(() => _dueDate = date);
        },
      ),
    );
  }

  Widget _timeField() {
    return _field(
      label: '时间',
      child: _picker(
        text:
            _dueTime == null
                ? '未设置'
                : '${_dueTime!.hour.toString().padLeft(2, '0')}:${_dueTime!.minute.toString().padLeft(2, '0')}',
        icon: LucideIcons.clock3,
        onTap: () async {
          final time = await showFxTimePicker(
            context: context,
            initialTime: _dueTime ?? TimeOfDay.now(),
          );
          if (time != null && mounted) setState(() => _dueTime = time);
        },
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
    return _field(
      label: '重复',
      child: SizedBox(
        width: double.infinity,
        child: FxSelect<String>(
          value: _repeatType,
          enabled: !_isSaving,
          options: labels.entries
              .map(
                (entry) => FxSelectOption<String>(
                  value: entry.key,
                  label: entry.value,
                ),
              )
              .toList(growable: false),
          onChanged:
              (value) => setState(() {
                _repeatType = value ?? 'none';
                if (_repeatType != 'weekly') _selectedWeekdays.clear();
              }),
        ),
      ),
    );
  }

  Widget _reminderField() {
    const values = <int, String>{
      -1: '不提醒',
      0: '准时',
      5: '提前 5 分钟',
      15: '提前 15 分钟',
      30: '提前 30 分钟',
      60: '提前 1 小时',
    };
    return _field(
      label: '提醒',
      child: SizedBox(
        width: double.infinity,
        child: FxSelect<int>(
          value: _reminderAdvanceMinutes,
          enabled: !_isSaving,
          options: values.entries
              .map(
                (entry) =>
                    FxSelectOption<int>(value: entry.key, label: entry.value),
              )
              .toList(growable: false),
          onChanged:
              (value) => setState(() => _reminderAdvanceMinutes = value ?? -1),
        ),
      ),
    );
  }

  Widget _field({required String label, required Widget child}) {
    return FxFormField(label: label, child: child);
  }

  Widget _fieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: SlowlightTypography.componentFieldLabel(context).copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _picker({
    required String text,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return FxInkWell(
      onTap: _isSaving ? null : onTap,
      borderRadius: BorderRadius.circular(SlowlightRadius.md),
      hoverColor: theme.colorScheme.onSurface.withValues(alpha: .04),
      focusColor: activePalette.accent.withValues(alpha: .08),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
                style: SlowlightTypography.componentControl(context),
              ),
            ),
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (widget.isEdit)
              FxButton(
                label: '删除',
                variant: FxButtonVariant.ghost,
                onPressed:
                    _isSaving ? null : () => Navigator.pop(context, 'delete'),
              ),
            FxButton(
              label: _isSaving ? '保存中…' : '保存',
              onPressed: _isSaving ? null : _save,
            ),
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
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }
}
