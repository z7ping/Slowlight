import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/tag.dart';
import '../models/task.dart';
import '../models/todo_list.dart';
import '../repositories/observation_tag_repository.dart';
import '../services/data_service.dart';
import '../services/api/task_api.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import 'tag_picker.dart';
import 'task_schedule_fields.dart';

/// 任务详情：桌面右侧面板，窄屏底部弹层。
class TaskDetailSheet extends StatefulWidget {
  final Task task;
  final bool isCreating;
  /// Only edits the initial draft. The stored task is unchanged until Save.
  final String? initialPriority;
  final List<TodoList> lists;
  final VoidCallback onChanged;
  final VoidCallback? onClose;
  final bool sidePanel;
  final ObservationTagRepository? tagsRepository;

  const TaskDetailSheet({
    super.key,
    required this.task,
    this.isCreating = false,
    this.initialPriority,
    required this.lists,
    required this.onChanged,
    this.onClose,
    this.sidePanel = false,
    this.tagsRepository,
  });

  static Future<void> show(
    BuildContext context, {
    required Task task,
    required List<TodoList> lists,
    required VoidCallback onChanged,
    bool isCreating = false,
    String? initialPriority,
  }) {
    final desktop = !SlowlightPlatformDensity.usesMobileTouchTargets &&
        MediaQuery.sizeOf(context).width >= SlowlightBreakpoints.tabletMin;
    if (desktop) {
      return showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: '关闭任务详情',
        barrierColor: Colors.black.withValues(alpha: .28),
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder:
            (dialogContext, _, __) => Align(
              alignment: Alignment.centerRight,
              child: Material(
                color: fxSurface(dialogContext),
                elevation: 18,
                shadowColor: Colors.black.withValues(alpha: .18),
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(SlowlightRadius.xl),
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: 420,
                  height: MediaQuery.sizeOf(dialogContext).height,
                  child: SafeArea(
                    child: TaskDetailSheet(
                      task: task,
                      isCreating: isCreating,
                      initialPriority: initialPriority,
                      lists: lists,
                      onChanged: onChanged,
                      sidePanel: true,
                    ),
                  ),
                ),
              ),
            ),
        transitionBuilder:
            (_, animation, __, child) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
      );
    }

    final editorKey = GlobalKey<TaskDetailSheetState>();
    return FxSheet.show<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      showCloseButton: false,
      draggable: false,
      isDismissible: false,
      onDismissRequested: () async {
        final editor = editorKey.currentState;
        if (editor != null) await editor._requestMobileClose();
      },
      padding: EdgeInsets.zero,
      backgroundColor: fxSurface(context),
      barrierColor: Colors.black.withValues(alpha: .45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SlowlightRadius.xl),
        ),
      ),
      // FxSheet owns the surface and keyboard avoidance; avoid an additional
      // clipping/decoration layer in the animated route.
      builder: (sheetContext) => Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          // The editor wraps its content until this viewport limit, then
          // scrolls its body while keeping the footer reachable.
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(sheetContext).width,
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .88,
          ),
          child: TaskDetailSheet(
            key: editorKey,
            task: task,
            isCreating: isCreating,
            initialPriority: initialPriority,
            lists: lists,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  /// Mobile task creation uses the exact same editor tree as editing.
  /// The draft has no persisted identity; only _save may create it.
  static Future<void> showCreate(
    BuildContext context, {
    List<TodoList>? lists,
    required VoidCallback onChanged,
    int? selectedListId,
    DateTime? initialDueDate,
    bool defaultDueToday = true,
    String initialTitle = '',
    String initialPriority = 'none',
    int? systemTagId,
  }) async {
    List<TodoList> available;
    try {
      available = lists ?? await DataService().getLists();
    } catch (_) {
      if (context.mounted) {
        FxNotice.showContent(context, const Text('清单读取失败，请稍后重试'));
      }
      return;
    }
    if (!context.mounted) return;
    if (available.isEmpty) {
      FxNotice.showContent(context, const Text('请先创建一个清单'));
      return;
    }

    final inboxes = available.where((list) => list.isInbox);
    final preferred = inboxes.isNotEmpty ? inboxes.first : available.first;
    final selected = [
      for (final list in available)
        if (list.id == selectedListId) list,
    ];
    final initialList = selected.isNotEmpty ? selected.first : preferred;
    final now = DateTime.now();
    final draft = Task(
      id: 0,
      listId: initialList.id,
      title: initialTitle,
      priority: initialPriority,
      dueDate: initialDueDate ??
          (defaultDueToday ? DateTime(now.year, now.month, now.day) : null),
      systemTagId: systemTagId,
      isCompleted: false,
      createdAt: now,
    );
    await show(
      context,
      task: draft,
      lists: available,
      onChanged: onChanged,
      isCreating: true,
    );
  }

  @override
  State<TaskDetailSheet> createState() => TaskDetailSheetState();
}

class TaskDetailSheetState extends State<TaskDetailSheet> {
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
  late bool _mobileReminderCustom;
  late List<Tag> _selectedTags;
  bool _saving = false;
  bool _mobileDirty = false;
  late final String _initialMobileSnapshot;
  bool _creationResultUnknown = false;
  bool _mobileExpanded = false;
  bool _allowMobilePop = false;

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
    _weekdays =
        task.repeatDays.isEmpty
            ? <int>{}
            : task.repeatDays
                .split(',')
                .map(int.tryParse)
                .whereType<int>()
                .toSet();
    _reminderAt = task.reminderAt;
    _reminderAdvanceMinutes = task.reminderAdvanceMinutes;
    _mobileReminderCustom = _reminderAt != null &&
        _reminderAt != buildTaskReminderAt(
          dueDate: _dueDate,
          dueTime: _dueTime,
          advanceMinutes: _reminderAdvanceMinutes,
        );
    _selectedTags = List<Tag>.from(task.tags);
    _mobileDirty = false;
    _initialMobileSnapshot = _mobileFormSnapshot();
    // Moving a task is an unsaved edit, not an immediate data mutation.
    // Take the snapshot before applying the requested target quadrant.
    if (!widget.isCreating &&
        widget.initialPriority != null &&
        widget.initialPriority != task.priority) {
      _priority = widget.initialPriority!;
      _mobileDirty = _mobileFormSnapshot() != _initialMobileSnapshot;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.sidePanel) return _mobileEditor();
    return Column(
      children: [
        _header(),
        FxSeparator.horizontal(height: 1, color: fxDivider(context)),
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


  String _mobileFormSnapshot() => [
        _title.text.trim(),
        _description.text.trim(),
        _mobileValueSnapshot(),
      ].join('\u0000');

  /// Desktop side panels share the same full-field snapshot as the mobile editor.
  /// Do not let list selection discard a draft or interrupt an in-flight save.
  Future<bool> confirmLeaveSidePanel() async {
    if (_saving || _creationResultUnknown) return false;
    if (_mobileFormSnapshot() == _initialMobileSnapshot) return true;
    final discard = await FxDialog.confirm(
      context: context,
      title: '放弃未保存的修改？',
      content: '切换任务或关闭详情后，当前未保存的修改将丢失。',
      confirmText: '放弃修改',
      destructive: true,
    );
    return mounted && discard == true;
  }

  Future<void> _requestDesktopClose() async {
    if (!await confirmLeaveSidePanel() || !mounted) return;
    _close();
  }

  void _mobileChanged([String? _]) {
    setState(() => _mobileDirty = _mobileFormSnapshot() != _initialMobileSnapshot);
  }

  Future<void> _mobileToggleCompleted() async {
    if (_saving || widget.isCreating) return;
    if (_mobileDirty) {
      FxNotice.showContent(context, const Text('请先保存修改，再更改任务状态'));
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.task.isCompleted) {
        await DataService().uncompleteTask(widget.task.id, null);
      } else {
        await DataService().completeTask(widget.task.id, null);
      }
      widget.onChanged();
      if (mounted) _close();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      FxNotice.showContent(
        context,
        const Text('任务状态更新结果未确认，请核对后重试'),
      );
    }
  }

  Future<void> _requestMobileClose({bool backFromSystem = false}) async {
    if (_saving) return;
    if (_mobileDirty || _creationResultUnknown) {
      final discard = await FxDialog.confirm(
        context: context,
        title: _creationResultUnknown
            ? '任务创建结果未确认'
            : widget.isCreating ? '放弃新建任务？' : '放弃未保存的修改？',
        content: _creationResultUnknown
            ? '请求可能已经成功。请关闭后核对任务列表，避免重复创建。'
            : widget.isCreating
                ? '尚未创建任务，关闭后将丢弃填写的内容。'
                : '本次编辑尚未保存，关闭后不会写入任务。',
        confirmText: '放弃修改',
        destructive: true,
      );
      if (discard != true || !mounted) return;
    }
    _close();
  }

  Widget _mobileEditor() {
    return PopScope(
      canPop: _allowMobilePop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestMobileClose(backFromSystem: true);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(),
          FxSeparator.horizontal(height: 1, color: fxDivider(context)),
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                SlowlightSpacing.xl,
                SlowlightSpacing.md,
                SlowlightSpacing.xl,
                SlowlightSpacing.xl,
              ),
              child: _mobileMainForm(),
            ),
          ),
          // The primary action stays reachable while the body scrolls or
          // the keyboard reduces the available viewport.
          _mobileFooter(),
        ],
      ),
    );
  }

  Widget _mobileMainForm() {
    final theme = Theme.of(context);
    final selectedList = [
      for (final list in widget.lists)
        if (list.id == _listId) list.name,
    ];
    final listLabel = selectedList.isNotEmpty ? selectedList.first : '未选择';
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    final dueLabel = _dueDate == null
        ? '不安排'
        : DateUtils.isSameDay(_dueDate, now)
            ? '今天'
            : DateUtils.isSameDay(_dueDate, tomorrow)
                ? '明天'
                : _dateLabel(_dueDate!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FxCard(
          key: const ValueKey('task.detail.workspace'),
          padding: const EdgeInsets.all(SlowlightSpacing.md),
          expanded: true,
          borderRadius: SlowlightRadius.lg,
          color: fxSurface(context),
          border: Border.all(color: theme.colorScheme.primary),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!widget.isCreating) FxIconButton(
                    key: const ValueKey('task.detail.complete'),
                    icon: widget.task.isCompleted
                        ? LucideIcons.circleCheck
                        : LucideIcons.circle,
                    iconSize: SlowlightIconSize.xl,
                    tooltip: widget.isCreating
                        ? '创建后可完成任务'
                        : widget.task.isCompleted
                            ? '恢复待办'
                            : '完成任务',
                    foregroundColor: widget.task.isCompleted
                        ? AppTheme.success
                        : theme.colorScheme.onSurfaceVariant,
                    onPressed: _saving || widget.isCreating
                        ? null
                        : _mobileToggleCompleted,
                  ),
                  if (!widget.isCreating)
                    const SizedBox(width: SlowlightSpacing.md),
                  Expanded(
                    child: FxInput(
                      key: const ValueKey('task.detail.title'),
                      controller: _title,
                      enabled: !_saving,
                      autofocus: widget.isCreating,
                      plain: true,
                      showPlainFocusUnderline: false,
                      minLines: 2,
                      maxLines: 4,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: SlowlightSpacing.xs,
                      ),
                      style: SlowlightTypography.emphasizedInput(context),
                      placeholder: '要做什么？',
                      maxLength: 180,
                      onChanged: _mobileChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SlowlightSpacing.md),
              Wrap(
                key: const ValueKey('task.detail.quickbar'),
                spacing: SlowlightSpacing.xs,
                runSpacing: SlowlightSpacing.xs,
                children: [
                  _mobilePropertyRow(
                    'list', LucideIcons.folder, '清单', listLabel,
                    quick: true,
                  ),
                  _mobilePropertyRow(
                    'due', LucideIcons.calendarDays, '日期',
                    dueLabel,
                    quick: true,
                  ),
                  _mobilePropertyRow(
                    'priority', LucideIcons.flag, '优先级',
                    switch (_priority) {
                      'urgent_important' => '重要 · 紧急',
                      'important' => '重要 · 不紧急',
                      'urgent' => '不重要 · 紧急',
                      'none' => '不重要 · 不紧急',
                      _ => '未设置',
                    },
                    quick: true,
                  ),
                  _mobilePropertyRow(
                    'tags', LucideIcons.tag, '标签',
                    _selectedTags.isEmpty
                        ? '未设置'
                        : _selectedTags.map((tag) => tag.name).join('、'),
                    quick: true,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: SlowlightSpacing.md),
        FxInkWell(
          key: const ValueKey('task.detail.moreSettings'),
          onTap: () => setState(() => _mobileExpanded = !_mobileExpanded),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: SlowlightControlSize.minTouchTarget,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '更多设置',
                    style: SlowlightTypography.componentSecondary(context),
                  ),
                ),
                Icon(
                  _mobileExpanded
                      ? LucideIcons.chevronUp
                      : LucideIcons.chevronDown,
                  size: SlowlightIconSize.sm,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_mobileExpanded) ...[
          FxInput(
            key: const ValueKey('task.detail.description'),
            controller: _description,
            enabled: !_saving,
            minLines: 2,
            maxLines: 4,
            style: SlowlightTypography.componentSecondary(context),
            placeholder: '描述（可选）',
            onChanged: _mobileChanged,
          ),
          const SizedBox(height: SlowlightSpacing.md),
          FxResponsiveFormGrid(
            minColumnWidth: 136,
            maxColumns: 2,
            horizontalGap: SlowlightSpacing.md,
            verticalGap: SlowlightSpacing.md,
            children: [
              _mobilePropertyRow(
                'time', LucideIcons.clock3, '时间',
                _dueTime == null ? '未设置' : _timeLabel(_dueTime!),
                compactSetting: true,
              ),
              _mobilePropertyRow(
                'repeat', LucideIcons.repeat, '重复',
                switch (_repeatType) {
                  'daily' => '每天',
                  'weekly' => '每周',
                  'monthly' => '每月',
                  'yearly' => '每年',
                  _ => '不重复',
                },
                compactSetting: true,
              ),
              _mobilePropertyRow(
                'reminder', LucideIcons.bell, '提醒',
                _mobileReminderLabel(),
                compactSetting: true,
              ),
            ],
          ),
        ],
        if (!widget.isCreating || _creationResultUnknown)
          Padding(
            padding: const EdgeInsets.only(top: SlowlightSpacing.xs),
            child: Text(
              _creationResultUnknown
                  ? '创建结果未确认，请先核对'
                  : _mobileDirty ? '有未保存的修改' : '已保存',
              key: const ValueKey('task.detail.status'),
              style: SlowlightTypography.caption(context).copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _mobilePropertyGroup(List<Widget> rows) {
    return FxCard(
      padding: const EdgeInsets.symmetric(
        horizontal: SlowlightSpacing.md,
      ),
      color: fxSurface(context),
      borderRadius: SlowlightRadius.lg,
      border: Border.all(color: fxBorder(context)),
      expanded: true,
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0)
              FxSeparator.horizontal(height: 1, color: fxDivider(context)),
            rows[index],
          ],
        ],
      ),
    );
  }

  Widget _mobilePropertyRow(
    String field,
    IconData icon,
    String label,
    String value, {
    bool quick = false,
    bool compactSetting = false,
  }) {
    final theme = Theme.of(context);
    final isUnset = value == '未设置';
    final showQuickValue = !isUnset || field == 'due' || field == 'list';
    final triggerKey = ValueKey('task.detail.property.$field');
    final hasQuickValue = field == 'list' ||
        field == 'due' ||
        (field == 'priority' && _priority != 'none') ||
        (field == 'tags' && _selectedTags.isNotEmpty);
    final content = quick
        ? Container(
            key: triggerKey,
            constraints: BoxConstraints(
              minWidth: SlowlightControlSize.minTouchTarget,
              minHeight: SlowlightControlSize.minTouchTarget,
              maxWidth: MediaQuery.sizeOf(context).width * .5,
            ),
            decoration: BoxDecoration(
              color: hasQuickValue ? fxSubtleSurface(context) : Colors.transparent,
              borderRadius: BorderRadius.circular(SlowlightRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SlowlightSpacing.md,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: SlowlightIconSize.md,
                    color: field == 'due'
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  if (showQuickValue) ...[
                    const SizedBox(width: SlowlightSpacing.xs),
                    Flexible(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SlowlightTypography.componentSecondary(context)
                            .copyWith(color: theme.colorScheme.onSurface),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          )
        : compactSetting
            ? Container(
                key: triggerKey,
                constraints: const BoxConstraints(minHeight: 60),
                padding: const EdgeInsets.all(SlowlightSpacing.md),
                decoration: BoxDecoration(
                  color: fxSurface(context),
                  borderRadius: BorderRadius.circular(SlowlightRadius.md),
                  border: Border.all(color: fxBorder(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: SlowlightIconSize.sm,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: SlowlightSpacing.xs),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SlowlightTypography.caption(context)
                                .copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: SlowlightSpacing.xs),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SlowlightTypography.componentControl(context),
                    ),
                  ],
                ),
              )
            : ConstrainedBox(
                key: triggerKey,
                constraints: const BoxConstraints(
                  minHeight: SlowlightControlSize.minTouchTarget,
                ),
                child: Row(
                  children: [
                    Icon(icon,
                        size: SlowlightIconSize.md,
                        color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: SlowlightSpacing.xl),
                    Expanded(
                      child: Text(
                        label,
                        style: SlowlightTypography.componentControl(context),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        value,
                        maxLines: 1,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: SlowlightTypography.componentSecondary(context)
                            .copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: SlowlightSpacing.md),
                    Icon(LucideIcons.chevronDown,
                        size: SlowlightIconSize.xs,
                        color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              );
    return FxMenu<String>(
      enabled: !_saving,
      tooltip: quick ? label : null,
      onOpened: () => FocusScope.of(context).unfocus(),
      constraints: BoxConstraints(
        minWidth: 220,
        maxWidth: MediaQuery.sizeOf(context).width - SlowlightSpacing.xl * 2,
        maxHeight: MediaQuery.sizeOf(context).height * .54,
      ),
      contentBuilder: (popoverContext, dismiss) => StatefulBuilder(
        builder: (popoverContext, refreshPopover) => SingleChildScrollView(
          padding: const EdgeInsets.all(SlowlightSpacing.md),
          child: _mobilePropertyPage(
            field,
            dismiss,
            () => refreshPopover(() {}),
          ),
        ),
      ),
      child: content,
    );
  }

  Widget _mobileChoice(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return FxInkWell(
      onTap: _saving ? null : onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: SlowlightControlSize.minTouchTarget,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: SlowlightTypography.componentControl(context).copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  )),
            ),
            if (selected)
              Icon(LucideIcons.check,
                  size: SlowlightIconSize.sm, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }

  String _mobileValueSnapshot() {
    final days = _weekdays.toList()..sort();
    final tags = _selectedTags.map((tag) => tag.id).toList()..sort();
    return [
      _listId,
      _dueDate?.toIso8601String(),
      _priority,
      _repeatType,
      _repeatInterval,
      days.join(','),
      _dueTime?.hour,
      _dueTime?.minute,
      _reminderAt?.toIso8601String(),
      _reminderAdvanceMinutes,
      _reminderAt != null && _mobileReminderCustom,
      tags.join(','),
    ].join('|');
  }

  void _mobileRecomputeRelativeReminder() {
    if (_mobileReminderCustom || _reminderAt == null) return;
    _reminderAt = buildTaskReminderAt(
      dueDate: _dueDate,
      dueTime: _dueTime,
      advanceMinutes: _reminderAdvanceMinutes,
    );
  }

  String _mobileReminderLabel() {
    if (_reminderAt == null) return '不提醒';
    if (!_mobileReminderCustom) {
      return switch (_reminderAdvanceMinutes) {
        0 => '准时',
        5 => '提前 5 分钟',
        10 => '提前 10 分钟',
        15 => '提前 15 分钟',
        30 => '提前 30 分钟',
        60 => '提前 1 小时',
        _ => '提前 ${_reminderAdvanceMinutes} 分钟',
      };
    }
    return '${_dateLabel(_reminderAt!)} '
        '${_timeLabel(TimeOfDay.fromDateTime(_reminderAt!))}';
  }

  void _mobileSelect(
    VoidCallback change, {
    bool stay = false,
    required VoidCallback dismiss,
    required VoidCallback refreshPopover,
  }) {
    final before = _mobileValueSnapshot();
    final oldDueDate = _dueDate;
    final oldDueTime = _dueTime;
    setState(() {
      change();
      if (oldDueDate != _dueDate || oldDueTime != _dueTime) {
        _mobileRecomputeRelativeReminder();
      }
      _mobileDirty = _mobileFormSnapshot() != _initialMobileSnapshot;
    });
    if (stay) {
      refreshPopover();
    } else {
      dismiss();
    }
  }

  Widget _mobilePropertyPage(
    String field,
    VoidCallback dismiss,
    VoidCallback refreshPopover,
  ) {
    final theme = Theme.of(context);
    Widget group(List<Widget> children) => _mobilePropertyGroup(children);
    switch (field) {
      case 'list':
        return group([
          if (widget.lists.isEmpty)
            Text('清单暂时不可用',
                style: SlowlightTypography.secondary(context))
          else
            for (final list in widget.lists)
              _mobileChoice(
                '${list.icon} ${list.name}',
                selected: _listId == list.id,
                onTap: () => _mobileSelect(() => _listId = list.id, dismiss: dismiss, refreshPopover: refreshPopover),
              ),
        ]);
      case 'priority':
        return group([
          for (final option in const [
            ('none', '不重要 · 不紧急'),
            ('urgent_important', '重要 · 紧急'),
            ('important', '重要 · 不紧急'),
            ('urgent', '不重要 · 紧急'),
          ])
            _mobileChoice(
              option.$2,
              selected: _priority == option.$1,
              onTap: () => _mobileSelect(() => _priority = option.$1, dismiss: dismiss, refreshPopover: refreshPopover),
            ),
        ]);
      case 'due':
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final tomorrow = DateTime(now.year, now.month, now.day + 1);
        bool matches(DateTime? other, DateTime date) =>
            other?.year == date.year &&
            other?.month == date.month &&
            other?.day == date.day;
        return group([
          _mobileChoice(
            '不设置',
            selected: _dueDate == null,
            onTap: () => _mobileSelect(() => _dueDate = null, dismiss: dismiss, refreshPopover: refreshPopover),
          ),
          _mobileChoice(
            '今天',
            selected: matches(_dueDate, today),
            onTap: () => _mobileSelect(() => _dueDate = today, dismiss: dismiss, refreshPopover: refreshPopover),
          ),
          _mobileChoice(
            '明天',
            selected: matches(_dueDate, tomorrow),
            onTap: () => _mobileSelect(() => _dueDate = tomorrow, dismiss: dismiss, refreshPopover: refreshPopover),
          ),
          _mobileChoice(
            '选择其他日期…',
            selected: false,
            onTap: () => _mobilePickDate(dismiss),
          ),
        ]);
      case 'repeat':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            group([
              for (final option in const [
                ('none', '不重复'),
                ('daily', '每天'),
                ('weekly', '每周'),
                ('monthly', '每月'),
                ('yearly', '每年'),
              ])
                _mobileChoice(
                  option.$2,
                  selected: _repeatType == option.$1,
                  onTap: () => _mobileSelect(() {
                    if (_repeatType != option.$1) {
                      _repeatType = option.$1;
                      // A new frequency starts at its natural 1× cadence.
                      _repeatInterval = 1;
                    }
                    if (_repeatType != 'weekly') _weekdays.clear();
                  }, stay: option.$1 == 'weekly', dismiss: dismiss, refreshPopover: refreshPopover),
                ),
            ]),
            if (_repeatType == 'weekly') ...[
              const SizedBox(height: SlowlightSpacing.xl),
              Text('选择星期',
                style: SlowlightTypography.caption(context).copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
              const SizedBox(height: SlowlightSpacing.md),
              Wrap(
                spacing: SlowlightSpacing.md,
                runSpacing: SlowlightSpacing.md,
                children: [
                  for (var i = 0; i < 7; i++)
                    FxChoiceChip(
                      label: const ['一','二','三','四','五','六','日'][i],
                      selected: _weekdays.contains(i + 1),
                      onTap: () => _mobileSelect(() {
                        if (!_weekdays.add(i + 1)) _weekdays.remove(i + 1);
                      }, stay: true, dismiss: dismiss, refreshPopover: refreshPopover),
                    ),
                ],
              ),
            ],
          ],
        );
      case 'time':
        return group([
          _mobileChoice(
            '不设置时间',
            selected: _dueTime == null,
            onTap: () => _mobileSelect(() => _dueTime = null, dismiss: dismiss, refreshPopover: refreshPopover),
          ),
          _mobileChoice(
            _dueTime == null ? '选择时间…' : '修改时间 · ${_timeLabel(_dueTime!)}',
            selected: _dueTime != null,
            onTap: () => _mobilePickTime(dismiss),
          ),
        ]);
      case 'reminder':
        return group([
          _mobileChoice(
            '不提醒',
            selected: _reminderAt == null,
            onTap: () => _mobileSelect(() {
              _reminderAt = null;
              _reminderAdvanceMinutes = 0;
              _mobileReminderCustom = false;
            }, dismiss: dismiss, refreshPopover: refreshPopover),
          ),
          for (final option in const [
            (0, '准时'),
            (5, '提前 5 分钟'),
            (10, '提前 10 分钟'),
            (15, '提前 15 分钟'),
            (30, '提前 30 分钟'),
            (60, '提前 1 小时'),
          ])
            _mobileChoice(
              option.$2,
              selected: _reminderAt != null &&
                  !_mobileReminderCustom &&
                  _reminderAdvanceMinutes == option.$1,
              onTap: () {
                if (_dueDate == null) {
                  FxNotice.showContent(
                    context,
                    const Text('请先安排日期，再设置相对提醒'),
                  );
                  return;
                }
                _mobileSelect(() {
                  _mobileReminderCustom = false;
                  _reminderAdvanceMinutes = option.$1;
                  _reminderAt = buildTaskReminderAt(
                    dueDate: _dueDate,
                    dueTime: _dueTime,
                    advanceMinutes: option.$1,
                  );
                }, dismiss: dismiss, refreshPopover: refreshPopover);
              },
            ),
          _mobileChoice(
            '自定义日期与时间…',
            selected: _reminderAt != null && _mobileReminderCustom,
            onTap: () => _mobilePickReminder(dismiss),
          ),
        ]);
      case 'tags':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TagPicker(
              label: '标签',
              enabled: !_saving,
              selectedTags: _selectedTags,
              onChanged: (tags) => _mobileSelect(() {
                _selectedTags = tags;
              }, stay: true, dismiss: dismiss, refreshPopover: refreshPopover),
            ),
            const SizedBox(height: SlowlightSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: FxButton(
                label: '完成',
                size: FxButtonSize.sm,
                onPressed: dismiss,
              ),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _mobilePickDate(VoidCallback dismiss) async {
    final before = _dueDate;
    await _pickDate();
    if (!mounted) return;
    if (_dueDate != before) {
      setState(() {
        _mobileRecomputeRelativeReminder();
        _mobileDirty = _mobileFormSnapshot() != _initialMobileSnapshot;
      });
      dismiss();
    }
  }

  Future<void> _mobilePickTime(VoidCallback dismiss) async {
    final before = _dueTime;
    await _pickTime();
    if (!mounted) return;
    if (_dueTime != before) {
      setState(() {
        _mobileRecomputeRelativeReminder();
        _mobileDirty = _mobileFormSnapshot() != _initialMobileSnapshot;
      });
      dismiss();
    }
  }

  Future<void> _mobilePickReminder(VoidCallback dismiss) async {
    final before = _mobileValueSnapshot();
    await _pickReminder();
    if (!mounted) return;
    if (_mobileValueSnapshot() != before) {
      setState(() {
        _mobileReminderCustom = true;
        _mobileDirty = _mobileFormSnapshot() != _initialMobileSnapshot;
      });
      dismiss();
    }
  }

  Widget _mobileFooter() {
    final canSave = widget.isCreating
        ? _title.text.trim().isNotEmpty && !_creationResultUnknown
        : _mobileDirty;
    // The latest Android prototype places Save outside the scrolling task
    // workbench. Reuse the existing FxButton and keep one stable action.
    return SafeArea(
      top: false,
      child: Container(
        key: const ValueKey('task.detail.fixedFooter'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          SlowlightSpacing.xxxl,
          SlowlightSpacing.md,
          SlowlightSpacing.xxxl,
          SlowlightSpacing.xl,
        ),
        decoration: BoxDecoration(
          color: fxSubtleSurface(context),
          border: Border(top: BorderSide(color: fxDivider(context))),
        ),
        child: Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 110),
            child: FxButton(
              key: const ValueKey('task.detail.primaryAction'),
              label: widget.isCreating
                  ? (_saving ? '添加中…' : '添加任务')
                  : (_saving ? '保存中…' : '保存修改'),
              variant: !canSave
                  ? FxButtonVariant.secondary
                  : FxButtonVariant.primary,
              size: FxButtonSize.sm,
              onPressed: _saving || !canSave ? null : _save,
            ),
          ),
        ),
      ),
    );
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (!widget.sidePanel && !_allowMobilePop) {
      setState(() => _allowMobilePop = true);
      // PopScope must rebuild before the route is allowed to exit.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } else {
      Navigator.pop(context);
    }
  }

  Widget _header() {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.sidePanel ? 20 : 16,
        widget.sidePanel ? 10 : 12,
        10,
        widget.sidePanel ? 8 : 6,
      ),
      child: Column(
        children: [
          // The sheet is intentionally non-draggable. Omit a misleading
          // drag handle and the extra header whitespace it introduced.
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.isCreating
                      ? (widget.sidePanel ? '新建任务' : '添加任务')
                      : '任务详情',
                  style: SlowlightTypography.cardTitle(context).copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (widget.task.isCompleted)
                FxChip(
                  label: '已完成',
                  backgroundColor: activePalette.accent.withValues(alpha: .12),
                  foregroundColor: activePalette.accent,
                  borderRadius: SlowlightRadius.pill,
                ),
              if (!widget.sidePanel && !widget.isCreating) ...[
                const SizedBox(width: 4),
                FxMenu<String>(
                  tooltip: '更多操作',
                  enabled: !_saving,
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(LucideIcons.ellipsis, size: 20),
                  ),
                  itemBuilder: (context) => [
                    FxMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.trash2,
                            size: 16,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '删除任务',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'delete') _delete();
                  },
                ),
              ],
              FxIconButton(
                tooltip: '关闭',
                onPressed: _saving
                    ? null
                    : () {
                        if (widget.sidePanel) {
                          _requestDesktopClose();
                        } else {
                          _requestMobileClose();
                        }
                      },
                icon: LucideIcons.x,
                foregroundColor: theme.colorScheme.onSurfaceVariant,
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
        FxInput(
          controller: _title,
          enabled: !_saving,
          style: SlowlightTypography.emphasizedInput(context),
          placeholder: '任务标题',
        ),
        const SizedBox(height: 8),
        FxInput(
          controller: _description,
          enabled: !_saving,
          minLines: 2,
          maxLines: 4,
          style: SlowlightTypography.componentSecondary(context),
          placeholder: '描述（可选）',
        ),
        const SizedBox(height: 24),
        _fieldLabel('清单'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: widget.lists
              .map((list) => FxChoiceChip(
                    label: '${list.icon} ${list.name}',
                    selected: _listId == list.id,
                    onTap: _saving ? null : () => setState(() => _listId = list.id),
                  ))
              .toList(growable: false),
        ),
        const SizedBox(height: 16),
        _fieldLabel('优先级'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _priorityChip('none', '不重要 · 不紧急'),
            _priorityChip('urgent_important', '高'),
            _priorityChip('important', '中'),
            _priorityChip('urgent', '低'),
          ],
        ),
        const SizedBox(height: 24),
        FxSeparator.horizontal(height: 1, color: fxDivider(context)),
        const SizedBox(height: 16),
        Text('时间安排', style: SlowlightTypography.sectionTitle(context)),
        const SizedBox(height: 12),
        FxResponsiveFormGrid(
          minColumnWidth: 136,
          maxColumns: 2,
          horizontalGap: 8,
          verticalGap: 10,
          children: [
            _pickerField(
              label: '到期日期',
              value: _dueDate == null ? '未设置' : _dateLabel(_dueDate!),
              icon: LucideIcons.calendarDays,
              onTap: _pickDate,
            ),
            _pickerField(
              label: '时间',
              value: _dueTime == null ? '未设置' : _timeLabel(_dueTime!),
              icon: LucideIcons.clock3,
              onTap: _pickTime,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _repeatField(),
        if (_repeatType == 'weekly') ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(7, (index) {
              final day = index + 1;
              const labels = ['一', '二', '三', '四', '五', '六', '日'];
              return FxChoiceChip(
                label: labels[index],
                selected: _weekdays.contains(day),
                onTap: _saving ? null : () => setState(() {
                  if (!_weekdays.add(day)) _weekdays.remove(day);
                }),
              );
            }),
          ),
        ],
        const SizedBox(height: 8),
        _settingRow(
          label: '提醒',
          value: _reminderAt == null
              ? '不提醒'
              : '${_dateLabel(_reminderAt!)} ${_timeLabel(TimeOfDay.fromDateTime(_reminderAt!))}',
          icon: LucideIcons.bell,
          onTap: _pickReminder,
        ),
        const SizedBox(height: 16),
        FxSeparator.horizontal(height: 1, color: fxDivider(context)),
        const SizedBox(height: 16),
        // 历史 system_tag_id 仅透传兼容，不再作为可编辑的分类概念展示。
        TagPicker(
          label: '标签',
          enabled: !_saving,
          selectedTags: _selectedTags,
          onChanged: (tags) => setState(() => _selectedTags = tags),
        ),
      ],
    );
  }

  Widget _repeatField() {
    const options = [
      FxSelectOption(value: 'none', label: '不重复'),
      FxSelectOption(value: 'daily', label: '每天'),
      FxSelectOption(value: 'weekly', label: '每周'),
      FxSelectOption(value: 'monthly', label: '每月'),
      FxSelectOption(value: 'yearly', label: '每年'),
    ];
    return Row(
      children: [
        Icon(LucideIcons.repeat, size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text('重复', style: SlowlightTypography.componentControl(context)),
        const SizedBox(width: 12),
        Expanded(
          child: FxSelect<String>(
            value: _repeatType,
            enabled: !_saving,
            options: options,
            onChanged: (value) => setState(() {
              _repeatType = value ?? 'none';
              if (_repeatType != 'weekly') _weekdays.clear();
            }),
          ),
        ),
      ],
    );
  }

  Widget _settingRow({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return FxInkWell(
      onTap: _saving ? null : onTap,
      borderRadius: BorderRadius.circular(SlowlightRadius.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Icon(icon, size: 16, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(label, style: SlowlightTypography.componentControl(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: SlowlightTypography.componentSecondary(context)
                    .copyWith(color: colors.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Icon(LucideIcons.chevronRight, size: 16, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _priorityChip(String value, String label) => FxChoiceChip(
    label: label,
    selected: _priority == value,
    selectionColor: switch (value) {
      'urgent_important' => AppTheme.priorityHigh,
      'important' => AppTheme.priorityMedium,
      'urgent' => AppTheme.priorityLow,
      _ => Theme.of(context).colorScheme.onSurface,
    },
    onTap: _saving ? null : () => setState(() => _priority = value),
  );

  Widget _pickerField({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        FxInkWell(
          onTap: _saving ? null : onTap,
          borderRadius: BorderRadius.circular(SlowlightRadius.md),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(SlowlightRadius.md),
              border: Border.all(color: fxBorder(context)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: SlowlightTypography.secondary(context),
                  ),
                ),
                Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: SlowlightTypography.componentFieldLabel(context).copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _footer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
        child: widget.sidePanel
            ? FxDialogActions(
                leading: FxButton(
                  label: '删除',
                  icon: LucideIcons.trash2,
                  variant: FxButtonVariant.ghost,
                  onPressed: _saving ? null : _delete,
                ),
                actions: [
                  FxButton(
                    label: _saving ? '保存中…' : '保存修改',
                    onPressed: _saving ? null : _save,
                  ),
                ],
              )
            : SizedBox(
                width: double.infinity,
                child: FxButton(
                  label: _saving ? '保存中…' : '保存修改',
                  onPressed: _saving ? null : _save,
                ),
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
      initialTime:
          _reminderAt == null
              ? (_dueTime ?? TimeOfDay.now())
              : TimeOfDay.fromDateTime(_reminderAt!),
    );
    if (time == null || !mounted) return;
    setState(() {
      _reminderAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _reminderAdvanceMinutes = 0;
    });
  }

  Future<void> _save() async {
    if (_saving || _creationResultUnknown) return;
    final title = _title.text.trim();
    final listId =
        _listId ?? (widget.lists.isEmpty ? null : widget.lists.first.id);
    if (title.isEmpty || listId == null) {
      FxNotice.showContent(
        context,
        Text(title.isEmpty ? '请输入任务名称' : '请选择清单后再保存'),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.isCreating) {
        await DataService().createTask(
          listId: listId,
          title: title,
          description:
              _description.text.trim().isEmpty ? null : _description.text.trim(),
          priority: _priority,
          dueDate: _dueDate,
          dueTime: _dueTime == null ? null : _timeLabel(_dueTime!),
          repeatType: _repeatType,
          repeatInterval: _repeatInterval,
          repeatDays:
              _weekdays.isEmpty ? '' : (_weekdays.toList()..sort()).join(','),
          reminderAt: _reminderAt,
          reminderAdvanceMinutes: _reminderAdvanceMinutes,
          tagIds: _selectedTags.map((tag) => tag.id).toList(),
          systemTagId: widget.task.systemTagId,
        );
      } else {
        await DataService().updateTask(
          localId: widget.task.id,
          serverId: null,
          listId: listId,
          title: title,
          description:
              _description.text.trim().isEmpty ? null : _description.text.trim(),
          priority: _priority,
          dueDate: _dueDate,
          dueTime: _dueTime == null ? null : _timeLabel(_dueTime!),
          repeatType: _repeatType,
          repeatInterval: _repeatInterval,
          repeatDays:
              _weekdays.isEmpty ? '' : (_weekdays.toList()..sort()).join(','),
          reminderAt: _reminderAt,
          reminderAdvanceMinutes: _reminderAdvanceMinutes,
          tagIds: _selectedTags.map((tag) => tag.id).toList(),
          systemTagId: widget.task.systemTagId,
          taskType: widget.task.taskType,
          moodBefore: widget.task.moodBefore,
          moodAfter: widget.task.moodAfter,
          isMilestone: widget.task.isMilestone,
          relatedQuestId: widget.task.relatedQuestId,
          obsidianLink: widget.task.obsidianLink,
          outputLevel: widget.task.outputLevel,
        );
      }
      widget.onChanged();
      if (mounted) _close();
    } catch (e) {
      if (!mounted) return;
      // A timed-out create may already be stored remotely. Disable a second
      // create attempt unless the data layer explicitly confirmed no write.
      final uncertain = widget.isCreating &&
          (e is! TaskCreateException || !e.confirmedNotCreated);
      setState(() {
        _saving = false;
        _creationResultUnknown = uncertain;
      });
      FxNotice.showContent(
        context,
        Text(uncertain
            ? '创建结果未确认，请先返回任务列表核对，避免重复创建'
            : widget.isCreating
                ? '创建失败，请检查输入后重试'
                : '保存结果未确认，请核对任务内容'),
      );
    }
  }

  Future<void> _delete() async {
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '删除任务',
      content: '确定删除「${widget.task.title}」吗？',
      confirmText: '删除',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    final notice = FxNotice.capture(context);
    final task = widget.task;
    try {
      await DataService().deleteTask(task.id, null);
      widget.onChanged();
      if (!mounted) return;
      _close();
      notice.clear();
      notice.showContent(
        Text('已删除「${task.title}」'),
        action: FxNoticeAction(
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
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      notice.showContent(Text('删除失败：$e'));
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
