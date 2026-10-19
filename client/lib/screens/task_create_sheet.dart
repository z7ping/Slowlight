import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/dimension.dart';
import '../models/task.dart';
import '../models/todo_list.dart';
import '../services/data_service.dart';
import '../services/task_dimension_assignment.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/task_dimension_field.dart';
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
        title: '记录任务',
        width: 520,
        child: editor,
      );
      return;
    }

    await FxSheet.show<void>(
      context: context,
      // 快捷表单按内容高度展示；保留下滑关闭手势，
      // 键盘出现时仍由 FxSheet 统一避让，不自动扩展成全屏。
      isScrollControlled: false,
      draggable: true,
      showDragHandle: false,
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
  final _dimensionAssignment = TaskDimensionAssignment();
  String? _selectedDimensionKey;
  bool _dimensionChanged = false;
  bool _showDimensionPicker = false;
  List<TodoList> _lists = const [];
  int? _selectedListId;
  late bool _dueToday;
  late String _selectedPriority;
  bool _loadingLists = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _dueToday = widget.defaultDueToday;
    _selectedPriority = _normalizePriority(widget.initialPriority);
    _loadLists();
    _loadInitialDimension();
  }

  @override
  void dispose() {
    _titleController.dispose();
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

  Future<void> _loadInitialDimension() async {
    if (widget.systemTagId == null) return;
    try {
      final key = await _dimensionAssignment.dimensionOf(widget.systemTagId);
      if (mounted && !_dimensionChanged) {
        setState(() => _selectedDimensionKey = key);
      }
    } catch (_) {
      // 原标签仍原样保留，读取维度失败不能阻止快速记录。
    }
  }

  TodoList? _inboxOf(List<TodoList> lists) {
    for (final list in lists) {
      if (list.isInbox) return list;
    }
    return null;
  }

  Widget _editorContent(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FxInput(
          controller: _titleController,
          autofocus: true,
          enabled: !_saving,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _createTask(),
          style: SlowlightTypography.body(context),
          placeholder: '例如：整理今天的会议记录',
        ),
        const SizedBox(height: 12),
        if (_loadingLists)
          Text(
            '正在读取清单…',
            style: SlowlightTypography.caption(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ..._quickLists().map(
                (list) => _QuickChip(
                  // 使用清单自身图标，与完整表单保持一致。
                  text: '${list.icon} ${list.name}',
                  selected: _selectedListId == list.id,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedListId = list.id);
                  },
                ),
              ),
              _QuickChip(
                icon: LucideIcons.calendarDays,
                text: '今天',
                selected: _dueToday,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _dueToday = !_dueToday);
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
                icon: LucideIcons.tag,
                text: DimensionCatalog.byKey(_selectedDimensionKey)?.name ?? '归属维度',
                selected: _selectedDimensionKey != null || _showDimensionPicker,
                onTap: () => setState(() => _showDimensionPicker = !_showDimensionPicker),
              ),
              if (!_dimensionChanged &&
                  widget.systemTagId != null &&
                  (widget.systemTagName ?? '').isNotEmpty)
                _DefaultHint(
                  icon: LucideIcons.tag,
                  text: widget.systemTagName!,
                ),
            ],
          ),
        if (_showDimensionPicker) ...[
          const SizedBox(height: SlowlightSpacing.xxxl),
          TaskDimensionField(
            selectedKey: _selectedDimensionKey,
            enabled: !_saving,
            onChanged: (key) => setState(() {
              _selectedDimensionKey = key;
              _dimensionChanged = true;
            }),
          ),
        ],
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

  Widget _editorActions() => FxDialogActions(
    actions: [
      FxButton(
        label: '更多设置',
        variant: FxButtonVariant.outline,
        size: FxButtonSize.sm,
        onPressed: _saving ? null : _openFullCreate,
      ),
      FxButton(
        label: _saving ? '记录中…' : '记录任务',
        size: FxButtonSize.sm,
        onPressed: _saving ? null : _createTask,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (widget.desktopDialog) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '记录任务',
              style: SlowlightTypography.cardTitle(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: _editorContent(context),
              ),
            ),
            const SizedBox(height: 12),
            _editorActions(),
          ],
        ),
      ),
    );
  }

  List<TodoList> _quickLists() {
    if (_lists.length <= 2) return _lists;
    TodoList? selected;
    for (final list in _lists) {
      if (list.id == _selectedListId) {
        selected = list;
        break;
      }
    }
    final result = <TodoList>[];
    if (selected != null) result.add(selected);
    for (final list in _lists) {
      if (result.any((item) => item.id == list.id)) continue;
      result.add(list);
      if (result.length == 2) break;
    }
    return result;
  }

  Future<void> _openFullCreate() async {
    final navigator = Navigator.of(context);
    final lists = _lists;
    final selectedListId = _selectedListId;
    final dueDate = _dueToday ? _today() : null;
    final defaultToToday = _dueToday;
    final initialTitle = _titleController.text;
    final initialPriority = _selectedPriority;
    final systemTagId = widget.systemTagId;
    final initialDimensionKey = _selectedDimensionKey;
    final dimensionChanged = _dimensionChanged;
    final onCreated = widget.onCreated;
    navigator.pop();
    await Future<void>.delayed(Duration.zero);
    if (!navigator.context.mounted) return;
    final created = await TaskCreateSheet.showFullCreate(
      navigator.context,
      lists: lists.isEmpty ? null : lists,
      selectedListId: selectedListId,
      defaultDueDate: dueDate,
      initialTitle: initialTitle,
      initialPriority: initialPriority,
      systemTagId: systemTagId,
      defaultToToday: defaultToToday,
      initialDimensionKey: initialDimensionKey,
      dimensionChanged: dimensionChanged,
    );
    if (created == true) onCreated?.call();
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
    try {
      final systemTagId = await _dimensionAssignment.resolve(
        dimensionKey: _selectedDimensionKey,
        originalTagId: widget.systemTagId,
        changed: _dimensionChanged,
      );
      final listId = _selectedListId;
      late Task task;
      if (listId == null) {
        task = await DataService().quickAddToInbox(
          title,
          systemTagId: systemTagId,
        );
        if (_selectedPriority != 'none' || _dueToday) {
          task = await DataService().updateTask(
            localId: task.id,
            listId: task.listId,
            title: task.title,
            description: task.description,
            priority: _selectedPriority,
            dueDate: _dueToday ? _today() : null,
            dueTime: task.dueTime,
            repeatType: task.repeatType,
            repeatInterval: task.repeatInterval,
            repeatDays: task.repeatDays,
            reminderAt: task.reminderAt,
            reminderAdvanceMinutes: task.reminderAdvanceMinutes,
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
          priority: _selectedPriority,
          dueDate: _dueToday ? _today() : null,
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
    final dateText = _dueToday ? ' · 今天' : '';
    final priorityText =
        _selectedPriority == 'none'
            ? ''
            : ' · ${_priorityLabel(_selectedPriority)}';
    final tagText =
        !_dimensionChanged && widget.systemTagId != null && (widget.systemTagName ?? '').isNotEmpty
            ? ' · ${widget.systemTagName}'
            : '';
    final dimension = DimensionCatalog.byKey(_selectedDimensionKey);
    final dimensionText = dimension == null ? '' : ' · ${dimension.name}';
    return '任务已记录到「$listName」$dateText$priorityText$dimensionText$tagText';
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
