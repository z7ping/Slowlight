import 'package:flutter/material.dart';

import '../models/todo_list.dart';
import '../models/observation_tag.dart';
import '../models/tag.dart';
import '../repositories/tag_repository.dart';
import '../services/task_dimension_assignment.dart';
import '../widgets/tag_choice_field.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/task_schedule_fields.dart';

class AddTaskScreen extends StatefulWidget {
  final List<TodoList> lists;
  final int? selectedListId;
  final DateTime? defaultDueDate;
  final String initialTitle;
  final String initialPriority;
  final int? systemTagId;
  final String? initialDimensionKey;
  final bool dimensionChanged;
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
    this.initialDimensionKey,
    this.dimensionChanged = false,
    this.isEdit = false,
    this.embedded = false,
  });

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _dimensionAssignment = TaskDimensionAssignment();
  final _tagRepository = TagRepository();
  List<Tag> _availableTags = const [];
  final Set<int> _selectedTagIds = {};
  bool _loadingTags = true;
  bool _tagLoadFailed = false;
  String? _selectedDimensionKey;
  bool _dimensionChanged = false;
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
    _selectedDimensionKey = widget.initialDimensionKey;
    _dimensionChanged = widget.dimensionChanged;
    // systemTagId 属于历史标签域，不可当成 canonical tags 的 id。
    _loadInitialDimension();
    _loadTags();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialDimension() async {
    if (_dimensionChanged || widget.systemTagId == null) return;
    try {
      final key = await _dimensionAssignment.dimensionOf(widget.systemTagId);
      if (mounted && !_dimensionChanged) {
        setState(() => _selectedDimensionKey = key);
      }
    } catch (_) {
      // 维度辅助信息暂时不可用时，仍保留已有观察标签。
    }
  }

  Future<void> _loadTags() async {
    if (mounted) setState(() => _loadingTags = true);
    try {
      final tags = await _tagRepository.getTags();
      if (!mounted) return;
      setState(() {
        _availableTags = tags;
        _loadingTags = false;
        _tagLoadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingTags = false;
        _tagLoadFailed = true;
      });
    }
  }

  List<ObservationTag> get _tagOptions => [
    for (final tag in _availableTags)
      ObservationTag(id: tag.id, name: tag.name, color: tag.color, icon: ''),
  ];

  Future<void> _save() async {
    if (_isSaving) return;
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
      // 历史预设维度独立保存；新标签仅走 canonical task_tags。
      final systemTagId = await _dimensionAssignment.resolve(
        dimensionKey: _selectedDimensionKey,
        originalTagId: widget.systemTagId,
        changed: _dimensionChanged,
      );
      final dueTime = formatTaskDueTime(_dueTime);
      final reminderAt = buildTaskReminderAt(
        dueDate: _dueDate,
        dueTime: _dueTime,
        advanceMinutes: _reminderAdvanceMinutes,
      );
      final repeatDays = formatTaskRepeatDays(_repeatType, _selectedWeekdays);

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
        tagIds: _selectedTagIds.toList(growable: false),
        systemTagId: systemTagId,
        taskType: 'daily',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _message('保存失败：$e');
    }
  }

  void _message(String text) {
    FxNotice.showContent(context, Text(text));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _editorShell(showBack: false);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(child: _editorShell(showBack: true)),
    );
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
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
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
        // 清单和优先级保持快捷 Chip，日程字段由快速/完整创建共享。
        FxResponsiveFormGrid(
          minColumnWidth: 240,
          children: [_listField(), _priorityField()],
        ),
        const SizedBox(height: 16),
        TaskScheduleFields(
          enabled: !_isSaving,
          dueDate: _dueDate,
          onDateChanged: (value) => setState(() => _dueDate = value),
          dueTime: _dueTime,
          onTimeChanged: (value) => setState(() => _dueTime = value),
          repeatType: _repeatType,
          onRepeatChanged: (value) => setState(() {
            _repeatType = value;
            if (value != 'weekly') _selectedWeekdays.clear();
          }),
          selectedWeekdays: _selectedWeekdays,
          onWeekdayToggled: (day) => setState(() {
            if (!_selectedWeekdays.add(day)) _selectedWeekdays.remove(day);
          }),
          reminderAdvanceMinutes: _reminderAdvanceMinutes,
          onReminderChanged: (value) => setState(() => _reminderAdvanceMinutes = value),
        ),
        const SizedBox(height: SlowlightSpacing.xxxl),
        TagChoiceField(
          tags: _tagOptions,
          selectedTagIds: _selectedTagIds,
          label: '标签（可多选）',
          enabled: !_isSaving && !_loadingTags && !_tagLoadFailed,
          onMultipleChanged: (ids) => setState(() {
            _selectedTagIds..clear()..addAll(ids);
          }),
        ),
        if (_loadingTags)
          Text('正在读取标签…', style: SlowlightTypography.caption(context)),
        if (_tagLoadFailed) ...[
          Text('标签加载失败，仍可不选标签创建任务。',
              style: SlowlightTypography.caption(context).copyWith(
                color: Theme.of(context).colorScheme.error,
              )),
          FxButton(
            label: '重新加载标签',
            variant: FxButtonVariant.outline,
            size: FxButtonSize.sm,
            onPressed: _isSaving ? null : _loadTags,
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

  Widget _field({required String label, required Widget child}) {
    return FxFormField(label: label, child: child);
  }

  Widget _footer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
        child: FxDialogActions(
          leading: widget.isEdit ? FxButton(
            label: '删除',
            variant: FxButtonVariant.ghost,
            onPressed: _isSaving ? null : () => Navigator.pop(context, 'delete'),
          ) : null,
          actions: [
            FxButton(
              label: _isSaving ? '保存中…' : '保存',
              onPressed: _isSaving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
