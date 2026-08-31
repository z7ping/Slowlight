import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/task.dart';
import '../models/todo_list.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
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
        width: 560,
        child: editor,
      );
      return;
    }

    await FxSheet.show<void>(
      context: context,
      isScrollControlled: true,
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
  }) async {
    final resolvedLists = lists ?? await DataService().getLists();
    if (!context.mounted) return false;
    if (resolvedLists.isEmpty) {
      FxNotice.showContent(context, Text('请先创建一个清单'));
      return false;
    }

    final desktop = MediaQuery.sizeOf(context).width >= 600;
    final editor = AddTaskScreen(
      lists: resolvedLists,
      selectedListId: selectedListId ?? resolvedLists.first.id,
      defaultDueDate:
          defaultDueDate ?? (defaultToToday ? DateTime.now() : null),
      initialTitle: initialTitle,
      initialPriority: initialPriority,
      systemTagId: systemTagId,
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
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SlowlightRadius.xl),
            side: BorderSide(color: fxBorder(dialogContext)),
          ),
          child: SizedBox(
            width: 600,
            height: (size.height * .72).clamp(480.0, 560.0),
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
                  icon: LucideIcons.folder,
                  text: list.name,
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
                text: _priorityLabel(_selectedPriority),
                selected: _selectedPriority != 'none',
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedPriority = _nextPriority(_selectedPriority);
                  });
                },
              ),
              if (widget.systemTagId != null &&
                  (widget.systemTagName ?? '').isNotEmpty)
                _DefaultHint(
                  icon: LucideIcons.tag,
                  text: widget.systemTagName!,
                ),
            ],
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
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
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
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.desktopDialog) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        child: SingleChildScrollView(child: _editorContent(context)),
      );
    }

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
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
              Flexible(child: SingleChildScrollView(child: _editorContent(context))),
            ],
          ),
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
      final listId = _selectedListId;
      late Task task;
      if (listId == null) {
        task = await DataService().quickAddToInbox(
          title,
          systemTagId: widget.systemTagId,
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
          systemTagId: widget.systemTagId,
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
        widget.systemTagId != null && (widget.systemTagName ?? '').isNotEmpty
            ? ' · ${widget.systemTagName}'
            : '';
    return '任务已记录到「$listName」$dateText$priorityText$tagText';
  }

  String _normalizePriority(String value) => switch (value) {
    'urgent_important' || 'important' || 'urgent' || 'none' => value,
    _ => 'none',
  };

  String _priorityLabel(String value) => switch (value) {
    'urgent_important' => '重要 · 紧急',
    'important' => '重要 · 不紧急',
    'urgent' => '不重要 · 紧急',
    _ => '不重要 · 不紧急',
  };

  String _nextPriority(String value) => switch (value) {
    'none' => 'urgent_important',
    'urgent_important' => 'important',
    'important' => 'urgent',
    _ => 'none',
  };
}

class _QuickChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _QuickChip({
    required this.icon,
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
