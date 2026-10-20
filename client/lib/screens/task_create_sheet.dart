import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/observation_tag.dart';
import '../repositories/observation_tag_repository.dart';
import '../models/task.dart';
import '../models/todo_list.dart';
import '../services/data_service.dart';

import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/tag_choice_field.dart';
import '../widgets/task_schedule_fields.dart';
import 'add_task_screen.dart';

/// 任务快速记录入口。
class TaskCreateSheet extends StatefulWidget {
  final bool quickMode;
  final bool desktopDialog;
  final int? systemTagId;
  final String? systemTagName;
  final String initialPriority;
  final bool defaultDueToday;
  final VoidCallback? onCreated;

  const TaskCreateSheet({
    super.key,
    this.quickMode = false,
    this.desktopDialog = false,
    this.systemTagId,
    this.systemTagName,
    this.initialPriority = 'none',
    this.defaultDueToday = true,
    this.onCreated,
  });

  static bool _useDesktopDialog(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 600 &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static Future<void> showQuickCreate(
    BuildContext context, {
    int? systemTagId,
    String? systemTagName,
    String initialPriority = 'none',
    bool defaultDueToday = true,
    VoidCallback? onCreated,
  }) async {
    final editor = TaskCreateSheet(
      quickMode: true,
      desktopDialog: _useDesktopDialog(context),
      systemTagId: systemTagId,
      systemTagName: systemTagName,
      initialPriority: initialPriority,
      defaultDueToday: defaultDueToday,
      onCreated: onCreated,
    );

    if (_useDesktopDialog(context)) {
      await FxDialog.show<void>(
        context: context,
        title: '添加任务',
        width: 520,
        child: editor,
      );
      return;
    }

    await FxSheet.show<void>(
      context: context,
      // 快捷表单按内容高度展示；保留下滑关闭手势，
      // 键盘出现时仍由 FxSheet 统一避让，不自动扩展成全屏。
      isScrollControlled: true,
      draggable: true,
      showDragHandle: false,
      // ShadSheet 的默认内边距与表单自身边距叠加会使移动端内容过窄。
      // 快捷表单由自身统一控制间距，其他 Sheet 不受影响。
      padding: EdgeInsets.zero,
      builder: (_) => editor,
    );
  }

  /// 完整任务表单：桌面紧凑居中弹窗，移动端整页。
  static Future<bool?> showFullCreate(
    BuildContext context, {
    List<TodoList>? lists,
    int? selectedListId,
    DateTime? defaultDueDate,
    String initialTitle = '',
    String initialPriority = 'none',
    int? systemTagId,
    bool defaultToToday = true,
    String? initialDimensionKey,
    bool dimensionChanged = false,
  }) async {
    final resolvedLists = lists ?? await DataService().getLists();
    if (!context.mounted) return false;
    if (resolvedLists.isEmpty) {
      FxNotice.showContent(context, Text('请先创建一个清单'));
      return false;
    }

    // Android 大屏/平板仍按移动端交互展示完整页，不能按宽度伪装桌面。
    final desktop = _useDesktopDialog(context);
    final editor = AddTaskScreen(
      lists: resolvedLists,
      selectedListId: selectedListId ?? resolvedLists.first.id,
      defaultDueDate:
          defaultDueDate ?? (defaultToToday ? DateTime.now() : null),
      initialTitle: initialTitle,
      initialPriority: initialPriority,
      systemTagId: systemTagId,
      initialDimensionKey: initialDimensionKey,
      dimensionChanged: dimensionChanged,
      embedded: desktop,
    );

    if (!desktop) {
      return Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => editor),
      );
    }

    return FxDialog.raw<bool>(
      context: context,
      barrierColor: FxDialog.barrierColor,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        return FxDialogSurface(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          backgroundColor: fxSurface(dialogContext),
          surfaceTintColor: Colors.transparent,
          padding: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SlowlightRadius.xl),
            side: BorderSide(color: fxBorder(dialogContext)),
          ),
          child: SizedBox(
            width: (size.width - 48).clamp(0.0, 680.0),
            height: (size.height - 48).clamp(0.0, 520.0),
            child: editor,
          ),
        );
      },
    );
  }

  @override
  State<TaskCreateSheet> createState() => _TaskCreateSheetState();
}

class _TaskCreateSheetState extends State<TaskCreateSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsRepository = ObservationTagRepository();
  List<ObservationTag> _availableTags = const [];
  late int? _selectedTagId;
  bool _showLists = true;
  bool _showTags = true;
  List<TodoList> _lists = const [];
  int? _selectedListId;
  late DateTime? _dueDate;
  TimeOfDay? _dueTime;
  String _repeatType = 'none';
  final Set<int> _selectedWeekdays = {};
  int _reminderAdvanceMinutes = -1;
  late String _selectedPriority;
  bool _loadingLists = true;
  bool _saving = false;
  String? _error;
  Key? _focusedMobileProperty;

  @override
  void initState() {
    super.initState();
    _dueDate = widget.defaultDueToday ? _today() : null;
    _selectedPriority = _normalizePriority(widget.initialPriority);
    _selectedTagId = widget.systemTagId;
    _loadLists();
    _loadTags();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadLists() async {
    try {
      final lists = await DataService().getLists();
      if (!mounted) return;
      final inbox = _inboxOf(lists);
      setState(() {
        _lists = lists;
        _selectedListId = inbox?.id ?? (lists.isEmpty ? null : lists.first.id);
        _loadingLists = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingLists = false);
    }
  }

  Future<void> _loadTags() async {
    try {
      final tags = await _tagsRepository.getAll();
      if (mounted) setState(() => _availableTags = tags);
    } catch (_) {
      // 标签读取失败不影响无标签记录，也不清空预设关联。
    }
  }

  TodoList? _inboxOf(List<TodoList> lists) {
    for (final list in lists) {
      if (list.isInbox) return list;
    }
    return null;
  }

  Widget _titleInput(BuildContext context) => FxInput(
    controller: _titleController,
    // 快捷记录默认聚焦标题，移动端同时弹出键盘。
    autofocus: true,
    onPressedOutside: (_) => FocusScope.of(context).unfocus(),
    enabled: !_saving,
    textInputAction: TextInputAction.done,
    onSubmitted: (_) => _createTask(),
    style: SlowlightTypography.body(context),
    placeholder: widget.desktopDialog
        ? '例如：整理今天的会议记录'
        : '要做什么？',
  );

  Widget _mobileEditorContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titleInput(context),
        const SizedBox(height: 12),
        FxResponsiveFormGrid(
          minColumnWidth: 136,
          maxColumns: 2,
          horizontalGap: 8,
          verticalGap: 8,
          children: [
            _mobileProperty(
              context,
              key: const ValueKey('task-property-list'),
              icon: LucideIcons.folder,
              label: _loadingLists ? '读取清单…' : _selectedListName(),
              selected: _selectedListId != null,
              onTap: _loadingLists || _saving ? null : _chooseMobileList,
            ),
            _mobileProperty(
              context,
              key: const ValueKey('task-property-date'),
              icon: LucideIcons.calendarDays,
              label: _dueDate == null
                  ? '未安排'
                  : _dueToday
                      ? '今天'
                      : '${_dueDate!.month}/${_dueDate!.day}',
              selected: _dueDate != null,
              onTap: _saving ? null : _chooseMobileDate,
            ),
            _mobileProperty(
              context,
              key: const ValueKey('task-property-priority'),
              icon: LucideIcons.flag,
              label: _selectedPriority == 'none'
                  ? '无优先级'
                  : _priorityLabel(_selectedPriority),
              selected: _selectedPriority != 'none',
              onTap: _saving ? null : _chooseMobilePriority,
            ),
            _mobileProperty(
              context,
              key: const ValueKey('task-property-tag'),
              icon: LucideIcons.tag,
              label: _selectedTagName() == '标签'
                  ? '无标签'
                  : _selectedTagName(),
              selected: _selectedTagId != null,
              onTap: _saving ? null : _chooseMobileTag,
            ),
          ],
        ),
        FxExpansionTile(
          key: const ValueKey('task-create-settings'),
          title: const Text('更多设置'),
          enabled: !_saving,
          tilePadding: const EdgeInsets.symmetric(vertical: 12),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [_advancedContent(context)],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: SlowlightTypography.caption(context).copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _mobileProperty(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final accent = activePalette.accent;
    final focused = _focusedMobileProperty == key;
    return FxInkWell(
      key: key,
      onTap: onTap,
      onFocusChange: (hasFocus) {
        setState(() {
          if (hasFocus) {
            _focusedMobileProperty = key;
          } else if (_focusedMobileProperty == key) {
            _focusedMobileProperty = null;
          }
        });
      },
      borderRadius: BorderRadius.circular(SlowlightRadius.md),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: focused
              ? accent.withValues(alpha: .08)
              : scheme.surfaceContainerLowest,
          border: Border.all(
            color: focused ? accent.withValues(alpha: .65) : scheme.outline,
          ),
          borderRadius: BorderRadius.circular(SlowlightRadius.md),
        ),
        child: Row(
          children: [
            Icon(icon, size: SlowlightIconSize.sm, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SlowlightTypography.componentControl(context).copyWith(
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              LucideIcons.chevronDown,
              size: SlowlightIconSize.xs,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Future<T?> _showMobileChoices<T>({
    required String title,
    required List<_QuickOption<T>> options,
    required T? selected,
  }) {
    FocusScope.of(context).unfocus();
    return FxSheet.show<T>(
      context: context,
      draggable: false,
      showDragHandle: false,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * .55;
        final height = math.min(maxHeight, (options.length * 52 + 72).toDouble());
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: SizedBox(
              height: height,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: SlowlightTypography.cardTitle(sheetContext),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options[index];
                        final active = option.value == selected;
                        return FxListTile(
                          density: FxListTileDensity.compact,
                          title: option.label,
                          leading: Icon(option.icon, size: SlowlightIconSize.md),
                          trailing: active
                              ? const Icon(LucideIcons.check, size: SlowlightIconSize.md)
                              : null,
                          selected: active,
                          selectedTileColor: activePalette.accent
                              .withValues(alpha: .10),
                          onTap: () => Navigator.of(sheetContext).pop(option.value),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _chooseMobileList() async {
    final id = await _showMobileChoices<int>(
      title: '选择清单',
      selected: _selectedListId,
      options: [
        for (final list in _lists)
          _QuickOption(value: list.id, label: '${list.icon} ${list.name}', icon: LucideIcons.folder),
      ],
    );
    if (mounted && id != null) setState(() => _selectedListId = id);
  }

  Future<void> _chooseMobileDate() async {
    final choice = await _showMobileChoices<int>(
      title: '安排日期',
      selected: _dueDate == null ? 0 : _dueToday ? 1 : 2,
      options: const [
        _QuickOption(value: 1, label: '今天', icon: LucideIcons.calendarDays),
        _QuickOption(value: 2, label: '选择日期…', icon: LucideIcons.calendarDays),
        _QuickOption(value: 0, label: '不安排日期', icon: LucideIcons.x),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 2) {
      final picked = await showFxDatePicker(
        context: context,
        initialDate: _dueDate ?? DateTime.now(),
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      );
      if (mounted && picked != null) setState(() => _dueDate = picked);
    } else {
      setState(() => _dueDate = choice == 1 ? _today() : null);
    }
  }

  Future<void> _chooseMobilePriority() async {
    final value = await _showMobileChoices<String>(
      title: '设置优先级',
      selected: _selectedPriority,
      options: const [
        _QuickOption(value: 'none', label: '无优先级', icon: LucideIcons.flag),
        _QuickOption(value: 'urgent_important', label: '高', icon: LucideIcons.flag),
        _QuickOption(value: 'important', label: '中', icon: LucideIcons.flag),
        _QuickOption(value: 'urgent', label: '低', icon: LucideIcons.flag),
      ],
    );
    if (mounted && value != null) setState(() => _selectedPriority = value);
  }

  Future<void> _chooseMobileTag() async {
    final id = await _showMobileChoices<int>(
      title: '选择标签',
      selected: _selectedTagId ?? -1,
      options: [
        const _QuickOption(value: -1, label: '无标签', icon: LucideIcons.tag),
        for (final tag in _availableTags)
          _QuickOption(value: tag.id, label: '#${tag.name}', icon: LucideIcons.tag),
      ],
    );
    if (mounted && id != null) {
      setState(() => _selectedTagId = id == -1 ? null : id);
    }
  }

  Widget _editorContent(BuildContext context) {
    if (!widget.desktopDialog) return _mobileEditorContent(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titleInput(context),
        const SizedBox(height: 12),
        if (_loadingLists)
          Text(
            '正在读取清单…',
            style: SlowlightTypography.caption(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else ...[
          FxExpansionTile(
            key: const ValueKey('task-create-lists'),
            initiallyExpanded: true,
            enabled: !_saving,
            tilePadding: const EdgeInsets.symmetric(vertical: 12),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            onExpansionChanged: (expanded) => setState(() => _showLists = expanded),
            title: Text(_showLists ? '清单' : '清单 · ${_selectedListName()}'),
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ..._lists.map(
                    (list) => _QuickChip(
                      text: '${list.icon} ${list.name}',
                      selected: _selectedListId == list.id,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedListId = list.id);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _QuickChip(
              icon: LucideIcons.calendarDays,
              text: _dueDate != null && !_dueToday
                  ? '${_dueDate!.month}/${_dueDate!.day}'
                  : '今天',
              selected: _dueDate != null,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _dueDate = _dueToday ? null : _today());
              },
            ),
            _QuickChip(
              icon: LucideIcons.flag,
              text: _selectedPriority == 'none'
                  ? '无优先级'
                  : '优先级：${_priorityLabel(_selectedPriority)}',
              selected: _selectedPriority != 'none',
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _selectedPriority = _nextPriority(_selectedPriority);
                });
              },
            ),
            _QuickChip(
              icon: _showTags ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              text: _selectedTagName(),
              selected: _selectedTagId != null,
              onTap: () => setState(() => _showTags = !_showTags),
            ),
          ],
        ),
        if (_showTags) ...[
          const SizedBox(height: SlowlightSpacing.xxxl),
          TagChoiceField(
            tags: _availableTags,
            selectedTagId: _selectedTagId,
            enabled: !_saving,
            onChanged: (id) => setState(() => _selectedTagId = id),
          ),
        ],
        FxExpansionTile(
          key: const ValueKey('task-create-settings'),
          title: const Text('更多设置'),
          enabled: !_saving,
          tilePadding: const EdgeInsets.symmetric(vertical: 12),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [_advancedContent(context)],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: SlowlightTypography.caption(
              context,
            ).copyWith(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _advancedContent(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FxInput(
        controller: _descriptionController,
        enabled: !_saving,
        minLines: 1,
        maxLines: 3,
        placeholder: '描述（可选）',
        style: SlowlightTypography.componentSecondary(context),
      ),
      SizedBox(height: widget.desktopDialog ? 16 : 12),
      TaskScheduleFields(
        compact: !widget.desktopDialog,
        enabled: !_saving,
        dueDate: _dueDate,
        onDateChanged: (date) => setState(() => _dueDate = date),
        dueTime: _dueTime,
        onTimeChanged: (time) => setState(() => _dueTime = time),
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
    ],
  );

  Widget _editorActions() => FxDialogActions(
    actions: [
      FxButton(
        label: _saving ? '添加中…' : '添加任务',
        size: widget.desktopDialog ? FxButtonSize.sm : FxButtonSize.md,
        onPressed: _saving ? null : _createTask,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (widget.desktopDialog) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: SingleChildScrollView(child: _editorContent(context))),
            const SizedBox(height: 12),
            _editorActions(),
          ],
        ),
      );
    }

    // FxSheet 已统一避让输入法，表单本身只负责内容高度与内部滚动。
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '添加任务',
                style: SlowlightTypography.cardTitle(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  // 输入时也能滚动表单，避免滚动触发键盘开合及布局跳动。
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.manual,
                  child: _editorContent(context),
                ),
              ),
              const SizedBox(height: 12),
              _editorActions(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createTask() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _saving) {
      if (title.isEmpty) setState(() => _error = '先写下要做的事情');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final notice = FxNotice.capture(context);
    final description = _descriptionController.text.trim();
    final dueTime = formatTaskDueTime(_dueTime);
    final repeatDays = formatTaskRepeatDays(_repeatType, _selectedWeekdays);
    final reminderAt = buildTaskReminderAt(
      dueDate: _dueDate,
      dueTime: _dueTime,
      advanceMinutes: _reminderAdvanceMinutes,
    );
    try {
      final systemTagId = _selectedTagId;
      final listId = _selectedListId;
      late Task task;
      if (listId == null) {
        task = await DataService().quickAddToInbox(
          title,
          systemTagId: systemTagId,
        );
        if (_selectedPriority != 'none' || _dueDate != null ||
            description.isNotEmpty || dueTime != null ||
            _repeatType != 'none' || _reminderAdvanceMinutes >= 0) {
          task = await DataService().updateTask(
            localId: task.id,
            listId: task.listId,
            title: task.title,
            description: description.isEmpty ? null : description,
            priority: _selectedPriority,
            dueDate: _dueDate,
            dueTime: dueTime,
            repeatType: _repeatType,
            repeatInterval: 1,
            repeatDays: repeatDays,
            reminderAt: reminderAt,
            reminderAdvanceMinutes: _reminderAdvanceMinutes < 0 ? 0 : _reminderAdvanceMinutes,
            tagIds: task.tags.map((tag) => tag.id).toList(growable: false),
            systemTagId: task.systemTagId,
            taskType: task.taskType,
            moodBefore: task.moodBefore,
            moodAfter: task.moodAfter,
            isMilestone: task.isMilestone,
            relatedQuestId: task.relatedQuestId,
            obsidianLink: task.obsidianLink,
            outputLevel: task.outputLevel,
          );
        }
      } else {
        task = await DataService().createTask(
          listId: listId,
          title: title,
          description: description.isEmpty ? null : description,
          priority: _selectedPriority,
          dueDate: _dueDate,
          dueTime: dueTime,
          repeatType: _repeatType,
          repeatInterval: 1,
          repeatDays: repeatDays,
          reminderAt: reminderAt,
          reminderAdvanceMinutes: _reminderAdvanceMinutes < 0 ? 0 : _reminderAdvanceMinutes,
          systemTagId: systemTagId,
        );
      }
      if (!mounted) return;
      HapticFeedback.lightImpact();
      widget.onCreated?.call();
      Navigator.pop(context);
      notice.showContent(Text(_createdText(task)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '记录失败：$e';
      });
    }
  }

  bool get _dueToday {
    if (_dueDate == null) return false;
    final today = _today();
    return _dueDate!.year == today.year &&
        _dueDate!.month == today.month && _dueDate!.day == today.day;
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String _selectedListName() {
    for (final list in _lists) {
      if (list.id == _selectedListId) return list.name;
    }
    return '收集箱';
  }

  String _createdText(Task task) {
    final listName = task.list?.name ?? _selectedListName();
    final dateText = _dueDate == null
        ? ''
        : _dueToday
            ? ' · 今天'
            : ' · ${_dueDate!.month}/${_dueDate!.day}';
    final priorityText =
        _selectedPriority == 'none'
            ? ''
            : ' · ${_priorityLabel(_selectedPriority)}';
    final tagText = _selectedTagId == null ? '' : ' · ${_selectedTagName()}';
    return '任务已添加到「$listName」$dateText$priorityText$tagText';
  }

  String _selectedTagName() {
    if (_selectedTagId == null) return '标签';
    for (final tag in _availableTags) {
      if (tag.id == _selectedTagId) return '#${tag.name}';
    }
    if (_selectedTagId == widget.systemTagId &&
        (widget.systemTagName ?? '').isNotEmpty) {
      return '#${widget.systemTagName}';
    }
    return '标签';
  }

  String _normalizePriority(String value) => switch (value) {
    'urgent_important' || 'important' || 'urgent' || 'none' => value,
    _ => 'none',
  };

  // 与完整表单的优先级选项保持同名，避免快捷记录出现冗长的第二行。
  String _priorityLabel(String value) => switch (value) {
    'urgent_important' => '高',
    'important' => '中',
    'urgent' => '低',
    _ => '无',
  };

  String _nextPriority(String value) => switch (value) {
    'none' => 'urgent_important',
    'urgent_important' => 'important',
    'important' => 'urgent',
    _ => 'none',
  };
}

class _QuickChip extends StatelessWidget {
  final IconData? icon;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _QuickChip({
    this.icon,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FxChoiceChip(
      label: text,
      icon: icon,
      selected: selected,
      selectionColor: activePalette.accent,
      onTap: onTap,
    );
  }
}

class _DefaultHint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DefaultHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return FxChip(
      label: text,
      icon: icon,
      backgroundColor: fxSubtleSurface(context),
      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      borderColor: fxBorder(context),
      borderRadius: 999,
    );
  }
}

class _QuickOption<T> {
  final T value;
  final String label;
  final IconData icon;

  const _QuickOption({
    required this.value,
    required this.label,
    required this.icon,
  });
}
