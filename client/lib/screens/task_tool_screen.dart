import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/task.dart';
import '../models/todo_list.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/task_detail_sheet.dart';
import '../widgets/task_swipe_row.dart';
import 'task_create_sheet.dart';

class TaskToolScreen extends StatefulWidget {
  final Future<List<dynamic>> Function()? dataLoader;
  // Independent loaders are test seams; production still uses DataService.
  final Future<List<dynamic>> Function()? taskDataLoader;
  final Future<List<TodoList>> Function()? listsLoader;
  final DataService? dataService;

  const TaskToolScreen({
    super.key,
    this.dataLoader,
    this.taskDataLoader,
    this.listsLoader,
    this.dataService,
  });

  @override
  State<TaskToolScreen> createState() => TaskToolScreenState();
}

class TaskToolScreenState extends State<TaskToolScreen> {
  bool _loading = true;
  int _segment = 0;
  List<Task> _today = const [];
  // The Android Today filter displays pending actions before completed facts.
  // Keep repository ordering for Windows / other layouts.
  List<Task> _mobileToday = const [];
  List<Task> _all = const [];
  List<Task> _completed = const [];
  List<TodoList> _lists = const [];
  bool _hasLoaded = false;
  bool _loadFailed = false;
  bool _listsLoading = false;
  bool _listLoadFailed = false;
  int _loadVersion = 0;
  Task? _selectedTask;
  bool _selectedTaskStale = false;
  GlobalKey<TaskDetailSheetState>? _selectedTaskEditorKey;
  bool _switchingDesktopTask = false;
  int? _revealedTaskId;
  final Set<int> _pendingTaskIds = <int>{};
  final ScrollController _mobileScrollController = ScrollController();
  DataService get _dataService => widget.dataService ?? DataService();

  @override
  void dispose() {
    _mobileScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Compare the fields this editor can write; timestamps/versions are not
  // always populated by every Local/Cloud API response.
  bool _sameTaskFields(Task a, Task b) {
    final aTags = a.tags.map((tag) => tag.id).toList()..sort();
    final bTags = b.tags.map((tag) => tag.id).toList()..sort();
    return a.id == b.id &&
        a.listId == b.listId && a.title == b.title &&
        a.description == b.description && a.priority == b.priority &&
        a.dueDate == b.dueDate && a.dueTime == b.dueTime &&
        a.repeatType == b.repeatType &&
        a.repeatInterval == b.repeatInterval &&
        a.repeatDays == b.repeatDays &&
        a.reminderAt == b.reminderAt &&
        a.reminderAdvanceMinutes == b.reminderAdvanceMinutes &&
        a.isCompleted == b.isCompleted &&
        a.completedAt == b.completedAt &&
        a.systemTagId == b.systemTagId &&
        a.taskType == b.taskType &&
        a.moodBefore == b.moodBefore &&
        a.moodAfter == b.moodAfter &&
        a.isMilestone == b.isMilestone &&
        a.relatedQuestId == b.relatedQuestId &&
        a.obsidianLink == b.obsidianLink &&
        a.outputLevel == b.outputLevel &&
        aTags.length == bTags.length &&
        List.generate(aTags.length, (index) => index)
            .every((index) => aTags[index] == bTags[index]);
  }

  Future<void> _load() async {
    final request = ++_loadVersion;
    final combinedLoader = widget.dataLoader != null;
    if (mounted) {
      setState(() {
        _loading = !_hasLoaded;
        _loadFailed = false;
        if (!combinedLoader) {
          _listsLoading = true;
          _listLoadFailed = false;
        }
      });
    }
    // A missing/slow collection must not block browsing already saved tasks.
    if (!combinedLoader) unawaited(_loadLists(request));
    try {
      final data = _dataService;
      final values = await (widget.dataLoader?.call() ??
          widget.taskDataLoader?.call() ??
          Future.wait<dynamic>([
            data.getTodayTasks(),
            data.getAllTasks(),
            data.getCompletedTasks(),
          ]));
      if (!mounted || request != _loadVersion) return;
      setState(() {
        _today = values[0] as List<Task>;
        _mobileToday = [
          ..._today.where((task) => !task.isCompleted),
          ..._today.where((task) => task.isCompleted),
        ];
        _all = values[1] as List<Task>;
        _completed = values[2] as List<Task>;
        if (combinedLoader) {
          _lists = values[3] as List<TodoList>;
          _listsLoading = false;
          _listLoadFailed = false;
        }
        final selected = _selectedTask;
        if (selected != null) {
          final latest = _all.cast<Task?>().firstWhere(
            (task) => task?.id == selected.id,
            orElse: () => null,
          );
          final hasDraft = _selectedTaskEditorKey?.currentState
                  ?.hasUncommittedWork ?? false;
          if (latest == null || !_sameTaskFields(selected, latest)) {
            if (hasDraft) {
              // A background refresh must never silently destroy or submit a
              // desktop draft based on a task that changed elsewhere.
              _selectedTaskStale = true;
            } else {
              _selectedTask = latest;
              _selectedTaskStale = false;
              _selectedTaskEditorKey = latest == null
                  ? null : GlobalKey<TaskDetailSheetState>();
            }
          } else {
            _selectedTask = latest;
            _selectedTaskStale = false;
          }
        }
        _revealedTaskId = null;
        _hasLoaded = true;
        _loadFailed = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _loadVersion) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _loadLists(int request) async {
    try {
      final lists = await (widget.listsLoader?.call() ??
          _dataService.getLists());
      if (!mounted || request != _loadVersion) return;
      setState(() {
        _lists = lists;
        _listsLoading = false;
        _listLoadFailed = false;
      });
    } catch (_) {
      if (!mounted || request != _loadVersion) return;
      setState(() {
        _listsLoading = false;
        _listLoadFailed = true;
      });
    }
  }

  Future<void> _retryLists() async {
    if (_listsLoading) return;
    setState(() => _listsLoading = true);
    await _loadLists(_loadVersion);
  }

  List<Task> get _visible => switch (_segment) {
    1 => _all,
    2 => _completed,
    _ => _today,
  };

  Widget _card({required Widget child, EdgeInsetsGeometry? padding}) {
    return FxCard(
      padding: padding ?? const EdgeInsets.all(SlowlightSpacing.xl),
      color: fxSurface(context),
      borderRadius: SlowlightRadius.lg,
      border: Border.all(color: fxBorder(context)),
      expanded: true,
      child: child,
    );
  }

  /// Called by the shell before removing the Tasks tool subtree.
  /// Delegates to the same editor guard as desktop task-to-task switching.
  Future<bool> confirmLeaveTool() async {
    final editor = _selectedTaskEditorKey?.currentState;
    return editor == null || await editor.confirmLeaveSidePanel();
  }

  Future<void> _changeSegment(int index) async {
    if (_switchingDesktopTask || index == _segment) return;
    _switchingDesktopTask = true;
    try {
      if (!await confirmLeaveTool() || !mounted) return;
      setState(() {
        _segment = index;
        _revealedTaskId = null;
        // A filtered list must not keep editing an unrelated selected task.
        _selectedTask = null;
        _selectedTaskStale = false;
        _selectedTaskEditorKey = null;
      });
    } finally {
      _switchingDesktopTask = false;
    }
  }

  Widget _segments() => FxSegmented(
    labels: const ['今天', '全部', '已完成'],
    selectedIndex: _segment,
    onChanged: _changeSegment,
    backgroundColor: fxSubtleSurface(context),
    selectedColor: fxSurface(context),
    borderRadius: SlowlightRadius.md,
  );

  Widget _taskActionBar() => FxActionBar(
    leading: _segments(),
    actions: [
      FxButton(
        label: '新建任务',
        icon: LucideIcons.plus,
        size: FxButtonSize.sm,
        onPressed: _create,
      ),
    ],
  );

  // Do not expose Undo for a write that was acknowledged but not reflected
  // in a fresh task list; an old cloud /complete endpoint toggles state.
  Future<bool> _refreshAndVerify(int taskId, bool completed) async {
    final request = _loadVersion + 1;
    await _load();
    if (!mounted || _loadFailed || request != _loadVersion) return false;
    return _all.any((task) =>
        task.id == taskId && task.isCompleted == completed);
  }

  Future<void> _toggle(Task task) async {
    // A previously failed refresh leaves stale completion flags on screen.
    // Do not call the toggle endpoint again until the list is confirmed.
    if (_loadFailed) {
      _message('任务列表刷新未确认，请先重试刷新再操作');
      return;
    }
    if (!_pendingTaskIds.add(task.id)) return;
    if (MediaQuery.sizeOf(context).width < 600) HapticFeedback.lightImpact();
    final wasCompleted = task.isCompleted;
    try {
      final updated = await _dataService.setTaskCompletion(
        task.id,
        null,
        completed: !wasCompleted,
        expectedCompleted: wasCompleted,
        expectedCompletedAt: wasCompleted ? task.completedAt : null,
      );
      if (!mounted) return;
      if (updated.isCompleted != !wasCompleted) {
        await _load();
        _message('任务状态已变化，请核对后再操作');
        return;
      }
      if (!await _refreshAndVerify(task.id, !wasCompleted)) {
        _message('任务更新已返回，但列表状态尚未确认，请刷新核对');
        return;
      }
      if (!mounted) return;
      FxNotice.showContent(
        context,
        Text(wasCompleted ? '已恢复待办' : '任务已完成'),
        variant: FxNoticeVariant.success,
        duration: wasCompleted || task.isRepeat || updated.completedAt == null
            ? const Duration(milliseconds: 2500)
            : const Duration(seconds: 8),
        placement: wasCompleted || task.isRepeat || updated.completedAt == null
            ? FxNoticePlacement.top
            : FxNoticePlacement.undo,
        // Recurring tasks may have spawned the next occurrence.
        action: wasCompleted || task.isRepeat || updated.completedAt == null
            ? null
            : FxNoticeAction(
                label: '撤销',
                onPressed: () => _undoCompletion(
                  task.id, expectedCompletedAt: updated.completedAt!,
                ),
              ),
      );
    } on StateError {
      await _load();
      if (mounted) _message('任务状态已变化，未重复切换，请核对后操作');
    } catch (_) {
      _message('任务操作结果未确认，请核对任务状态');
    } finally {
      _pendingTaskIds.remove(task.id);
    }
  }

  Future<void> _undoCompletion(
    int taskId, {required DateTime expectedCompletedAt}) async {
    if (!_pendingTaskIds.add(taskId)) return;
    try {
      // A stale toast must not undo another completion cycle. The server
      // compares both status and the exact completion timestamp atomically.
      final tasks = await _dataService.getAllTasks();
      final current = tasks.cast<Task?>().firstWhere(
        (task) => task?.id == taskId,
        orElse: () => null,
      );
      if (!mounted) return;
      if (current == null || current.isRepeat) {
        _message('无法确认可撤销的原任务，请先核对任务列表');
        return;
      }
      if (!current.isCompleted) {
        await _load();
        _message('任务已是待办状态，无需再次撤销');
        return;
      }
      if (current.completedAt == null ||
          !current.completedAt!.isAtSameMomentAs(expectedCompletedAt)) {
        await _load();
        _message('任务已有新的完成记录，旧撤销已失效');
        return;
      }
      final updated = await _dataService.setTaskCompletion(
        taskId,
        null,
        completed: false,
        expectedCompleted: true,
        expectedCompletedAt: expectedCompletedAt,
      );
      if (!mounted) return;
      if (updated.isCompleted ||
          !await _refreshAndVerify(taskId, false)) {
        _message('撤销回执尚未核实，请刷新任务列表确认');
        return;
      }
      _message('已恢复待办');
    } on StateError {
      await _load();
      if (mounted) _message('任务状态已变化，旧撤销未执行');
    } catch (_) {
      _message('撤销状态未确认，请核对任务后再操作');
    } finally {
      _pendingTaskIds.remove(taskId);
    }
  }

  bool _sameDueDate(DateTime? a, DateTime? b) =>
      a == null ? b == null : b != null && a.isAtSameMomentAs(b);

  Future<void> _undoPostpone(
    int taskId, {
    required DateTime expectedDueDate,
    required DateTime? originalDueDate,
  }) async {
    if (!_pendingTaskIds.add(taskId)) return;
    try {
      final restored = await _dataService.restorePostponedDueDate(
        taskId,
        null,
        expectedDueDate: expectedDueDate,
        originalDueDate: originalDueDate,
      );
      if (!mounted) return;
      if (!_sameDueDate(restored.dueDate, originalDueDate)) {
        _message('撤销回执尚未核实，请查看任务日期');
        return;
      }
      final request = _loadVersion + 1;
      await _load();
      if (!mounted) return;
      if (_loadFailed || request != _loadVersion ||
          !_all.any((item) =>
              item.id == taskId && _sameDueDate(item.dueDate, originalDueDate))) {
        _message('撤销已返回，但任务列表尚未确认，请刷新核对');
        return;
      }
      _message('已撤销顺延');
    } on StateError {
      _message('任务日期已变化，未执行撤销，请核对后再操作');
    } catch (_) {
      _message('顺延撤销结果未确认，请核对任务日期');
    } finally {
      _pendingTaskIds.remove(taskId);
    }
  }

  Future<void> _postpone(Task task) async {
    if (_loadFailed) {
      _message('任务列表刷新未确认，请先重试刷新再操作');
      return;
    }
    if (!_pendingTaskIds.add(task.id)) return;
    if (MediaQuery.sizeOf(context).width < 600) HapticFeedback.lightImpact();
    try {
      final postponed = await _dataService.postponeTask(task.id, null);
      if (!mounted) return;
      final request = _loadVersion + 1;
      await _load();
      if (!mounted) return;
      final current = _all.cast<Task?>().firstWhere(
        (item) => item?.id == task.id,
        orElse: () => null,
      );
      if (_loadFailed || request != _loadVersion || current == null ||
          !_sameDueDate(current.dueDate, postponed.dueDate)) {
        _message('顺延已返回，但列表刷新未确认，请查看任务日期');
        return;
      }
      final expectedDueDate = postponed.dueDate;
      FxNotice.showContent(
        context,
        const Text('已顺延到明天'),
        variant: FxNoticeVariant.success,
        duration: expectedDueDate != null &&
                !_sameDueDate(task.dueDate, expectedDueDate) &&
                !current.isCompleted
            ? const Duration(seconds: 8)
            : const Duration(milliseconds: 2500),
        placement: expectedDueDate != null &&
                !_sameDueDate(task.dueDate, expectedDueDate) &&
                !current.isCompleted
            ? FxNoticePlacement.undo
            : FxNoticePlacement.top,
        action: expectedDueDate != null &&
                !_sameDueDate(task.dueDate, expectedDueDate) &&
                !current.isCompleted
            ? FxNoticeAction(
                label: '撤销',
                onPressed: () => _undoPostpone(
                  task.id,
                  expectedDueDate: expectedDueDate,
                  originalDueDate: task.dueDate,
                ),
              )
            : null,
      );
    } catch (_) {
      _message('顺延结果未确认，请查看任务日期');
    } finally {
      _pendingTaskIds.remove(task.id);
    }
  }

  bool _canEditTask() {
    if (_listsLoading) {
      _message('正在读取清单，请核对后再编辑任务');
      return false;
    }
    if (_listLoadFailed) {
      _message('清单读取失败，请先重试后再编辑任务');
      return false;
    }
    if (_lists.isEmpty) {
      _message('清单暂时不可用，请先创建清单');
      return false;
    }
    return true;
  }

  void _open(Task task) {
    if (!_canEditTask()) return;
    final availableWidth =
        context.size?.width ?? MediaQuery.sizeOf(context).width;
    if (availableWidth >= 860) {
      _selectDesktopTask(task);
      return;
    }
    TaskDetailSheet.show(context, task: task, lists: _lists, onChanged: _load);
  }

  Future<void> _selectDesktopTask(Task task) async {
    if (_switchingDesktopTask || _selectedTask?.id == task.id) return;
    _switchingDesktopTask = true;
    try {
      if (!await confirmLeaveTool()) return;
      if (!mounted) return;
      setState(() {
        _selectedTask = task;
        _selectedTaskStale = false;
        // A different task must receive a fresh form state and initial snapshot.
        _selectedTaskEditorKey = GlobalKey<TaskDetailSheetState>();
      });
    } finally {
      _switchingDesktopTask = false;
    }
  }

  Future<void> _create() async {
    if (!_canEditTask()) return;
    // Mobile creates and edits through one editor and the same property rows.
    // Keep the existing desktop create dialog untouched.
    if (SlowlightPlatformDensity.usesMobileTouchTargets) {
      await TaskDetailSheet.showCreate(
        context,
        lists: _lists,
        onChanged: _load,
      );
      return;
    }
    final created = await TaskCreateSheet.showFullCreate(
      context,
      lists: _lists,
      // Use the existing inbox-first default in showFullCreate instead of
      // accidentally selecting an arbitrary first collection.
      defaultDueDate: DateTime.now(),
    );
    if (created == true && mounted) await _load();
  }

  void _message(String text) {
    if (!mounted) return;
    FxNotice.showContent(context, Text(text));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_hasLoaded) {
      return SlowlightPlatformDensity.usesMobileTouchTargets
          ? const FxSkeletonPage(kind: FxSkeletonPageKind.tasks)
          : const Center(child: FxCircularProgress());
    }
    if (_loadFailed && !_hasLoaded) {
      return Center(child: FxEmptyState(
        icon: LucideIcons.triangleAlert,
        title: '任务读取失败',
        subtitle: '暂时无法获取任务记录，请检查数据服务后重试。',
        action: FxButton(label: '重试', onPressed: _load),
      ));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 600;
        final desktop = constraints.maxWidth >= 860;
        return FxRefresh(
          onRefresh: _load,
          child:
              desktop
                  ? _desktopContent()
                  : mobile
                      ? _mobileTaskList()
                      : _mediumTaskList(),
        );
      },
    );
  }

  Widget _mediumTaskList() {
    final visible = _visible;
    final edge = BorderSide(color: fxBorder(context));
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: SlowlightPageInsets.scroll(context, bottom: 72),
          sliver: SliverList.builder(
            itemCount: 1 + (visible.isEmpty ? 1 : visible.length),
            itemBuilder: (context, position) {
              if (position == 0) {
                return Column(
                  children: [
                    _taskActionBar(),
                    if (_loadFailed) _refreshErrorNotice(),
                    if (_listLoadFailed) _listErrorNotice(),
                    const SizedBox(height: SlowlightSpacing.xl),
                  ],
                );
              }
              if (visible.isEmpty) return _card(child: _emptyState());
              final index = position - 1;
              final task = visible[index];
              final first = index == 0;
              final last = index == visible.length - 1;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: fxSurface(context),
                  border: Border(
                    left: edge,
                    right: edge,
                    top: first ? edge : BorderSide.none,
                    bottom: last ? edge : BorderSide.none,
                  ),
                  borderRadius: BorderRadius.vertical(
                    top: first
                        ? const Radius.circular(SlowlightRadius.lg)
                        : Radius.zero,
                    bottom: last
                        ? const Radius.circular(SlowlightRadius.lg)
                        : Radius.zero,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SlowlightSpacing.xl,
                  ),
                  child: _taskRow(task),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // The Android task workspace follows the confirmed compact-list prototype.
  // Keep the app-bar title owned by the shell; avoid a second page heading.
  Widget _mobileTaskList() {
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final dateLabel = '${now.month}月${now.day}日 · 星期${weekdays[now.weekday - 1]}';
    final remaining = _all.where((task) => !task.isCompleted).length;
    final visible = _segment == 0 ? _mobileToday : _visible;
    final title = switch (_segment) {
      1 => '所有任务',
      2 => '已完成',
      _ => '今日相关',
    };
    final edge = BorderSide(color: fxBorder(context));

    // SliverList builds only visible task rows; a Column eagerly created the
    // entire '全部' list on every state change.
    return CustomScrollView(
      key: const ValueKey('tasks.mobile.list'),
      controller: _mobileScrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: SlowlightPageInsets.scroll(context, bottom: 72),
          sliver: SliverList.builder(
            itemCount: 1 + (visible.isEmpty ? 1 : visible.length),
            itemBuilder: (context, position) {
              if (position == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dateLabel,
                                style: SlowlightTypography.sectionTitle(context),
                              ),
                              const SizedBox(height: SlowlightSpacing.xs),
                              Text(
                                '${remaining} 项待完成',
                                style: SlowlightTypography.caption(context)
                                    .copyWith(
                                  color: Theme.of(context)
                                      .colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FxButton(
                          label: '新建',
                          icon: LucideIcons.plus,
                          size: FxButtonSize.sm,
                          variant: FxButtonVariant.outline,
                          onPressed: _create,
                        ),
                      ],
                    ),
                    const SizedBox(height: SlowlightSpacing.xl),
                    _mobileFilters(),
                    if (_loadFailed) _refreshErrorNotice(),
                    if (_listLoadFailed) _listErrorNotice(),
                    const SizedBox(height: SlowlightSpacing.xl),
                    FxSectionHeader(
                      title: title,
                      trailing: '${visible.length} 项',
                    ),
                    const SizedBox(height: SlowlightSpacing.md),
                  ],
                );
              }
              if (visible.isEmpty) {
                return _card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: SlowlightSpacing.page,
                    ),
                    child: _emptyState(),
                  ),
                );
              }

              final index = position - 1;
              final task = visible[index];
              final first = index == 0;
              final last = index == visible.length - 1;
              return DecoratedBox(
                key: ValueKey('tasks.mobile.shell.${task.id}'),
                decoration: BoxDecoration(
                  color: fxSurface(context),
                  border: Border(
                    left: edge,
                    right: edge,
                    top: first ? edge : BorderSide.none,
                    bottom: last ? edge : BorderSide.none,
                  ),
                  borderRadius: BorderRadius.vertical(
                    top: first
                        ? const Radius.circular(SlowlightRadius.lg)
                        : Radius.zero,
                    bottom: last
                        ? const Radius.circular(SlowlightRadius.lg)
                        : Radius.zero,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SlowlightSpacing.md,
                  ),
                  child: SlowlightPlatformDensity.usesMobileTouchTargets
                      ? _swipeTaskRow(task, last: last)
                      : _taskRow(task, compactMobile: true, lastMobile: last),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _mobileFilters() {
    final items = <(String, int)>[
      ('今天', _today.length),
      ('全部', _all.length),
      ('已完成', _completed.length),
    ];
    final theme = Theme.of(context);
    return Wrap(
      key: const ValueKey('tasks.mobile.filters'),
      spacing: SlowlightSpacing.page,
      runSpacing: SlowlightSpacing.xs,
      children: [
        for (var i = 0; i < items.length; i++)
          FxInkWell(
            key: ValueKey('tasks.mobile.filter.${i}'),
            onTap: () {
              if (_segment == i) return;
              if (_mobileScrollController.hasClients) {
                _mobileScrollController.jumpTo(0);
              }
              setState(() {
                _segment = i;
                _revealedTaskId = null;
              });
            },
            child: AnimatedContainer(
              duration: MediaQuery.of(context).disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(
                minHeight: SlowlightControlSize.minTouchTarget,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: SlowlightSpacing.xs,
                vertical: SlowlightSpacing.md,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: _segment == i
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(items[i].$1,
                      style: SlowlightTypography.componentControl(context)
                          .copyWith(
                        color: _segment == i
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight:
                            _segment == i ? FontWeight.w700 : FontWeight.w500,
                      )),
                  const SizedBox(width: SlowlightSpacing.xs),
                  Text(items[i].$2.toString(),
                      style: SlowlightTypography.caption(context).copyWith(
                        color: _segment == i
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      )),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _listErrorNotice() => Padding(
    padding: const EdgeInsets.only(top: SlowlightSpacing.xs),
    child: FxCard(
      padding: const EdgeInsets.all(SlowlightSpacing.md),
      expanded: true,
      child: Row(
        children: [
          Expanded(child: Text(
            '清单读取失败，已有任务仍可浏览；创建和编辑请先重试。',
            style: SlowlightTypography.secondary(context),
          )),
          FxButton(
            label: _listsLoading ? '读取中…' : '重试清单',
            size: FxButtonSize.sm,
            variant: FxButtonVariant.ghost,
            onPressed: _listsLoading ? null : _retryLists,
          ),
        ],
      ),
    ),
  );

  Widget _refreshErrorNotice() => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: FxCard(
      padding: const EdgeInsets.all(12),
      expanded: true,
      child: Row(
        children: [
          const Icon(LucideIcons.triangleAlert, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(
            '刷新失败，仍显示上次加载的任务',
            style: SlowlightTypography.secondary(context),
          )),
          FxButton(
            label: _loading ? '重试中…' : '重试',
            size: FxButtonSize.sm,
            variant: FxButtonVariant.ghost,
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
    ),
  );

  Widget _desktopContent() {
    // Master prototype: one open task workspace, not two oversized cards.
    // Keep the existing Fx action bar, lazy list and shared task editor.
    return Padding(
      padding: SlowlightPageInsets.scroll(
        context,
        bottom: SlowlightSpacing.page,
      ),
      child: Column(
        children: [
          _taskActionBar(),
          if (_loadFailed) _refreshErrorNotice(),
          if (_listLoadFailed) _listErrorNotice(),
          const SizedBox(height: SlowlightSpacing.xl),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 9,
                  child: _visible.isEmpty
                      ? _emptyState()
                      : ListView.builder(
                          itemCount: _visible.length,
                          itemBuilder: (context, index) {
                            final task = _visible[index];
                            return _taskRow(
                              task,
                              selected: _selectedTask?.id == task.id,
                            );
                          },
                        ),
                ),
                const SizedBox(width: 20),
                FxSeparator.vertical(
                  width: 1,
                  color: fxBorder(context),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 11,
                  child: _selectedTask == null
                      ? _desktopEmptyDetail()
                      : Column(
                          children: [
                            if (_selectedTaskStale)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    const Icon(LucideIcons.triangleAlert, size: 16),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        '任务已在其他位置变更，草稿已保留；请核对后再编辑',
                                      ),
                                    ),
                                    FxButton(
                                      label: '重试',
                                      variant: FxButtonVariant.ghost,
                                      size: FxButtonSize.sm,
                                      onPressed: _load,
                                    ),
                                  ],
                                ),
                              ),
                            Expanded(
                              child: TaskDetailSheet(
                                key: _selectedTaskEditorKey,
                                task: _selectedTask!,
                                lists: _lists,
                                sidePanel: true,
                                writeBlocked: _selectedTaskStale,
                                onClose: () => setState(() {
                                  _selectedTask = null;
                                  _selectedTaskStale = false;
                                  _selectedTaskEditorKey = null;
                                }),
                                onChanged: _load,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => FxEmptyState(
    icon: LucideIcons.listTodo,
    title: _segment == 2 ? '还没有已完成任务' : '这里暂时没有任务',
    subtitle: _segment == 0 ? '今天可以从一件真正想推进的事开始' : '切换其他筛选看看',
  );

  Widget _desktopEmptyDetail() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.mousePointerClick,
            size: SlowlightIconSize.xl,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: SlowlightSpacing.xl),
          Text(
            '选择一项任务查看详情',
            style: SlowlightTypography.body(context).copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '列表用于浏览，日期、描述和提醒在这里调整。',
            style: SlowlightTypography.secondary(context).copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _swipeTaskRow(Task task, {bool last = false}) {
    // Keep completed and pending items on the same 48dp row rhythm.
    // Completed tasks retain the click target but have no swipe actions.
    final row = _taskRow(
      task,
      verticalPadding: 0,
      compactMobile: true,
      lastMobile: last,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SlowlightSpacing.xs / 2),
      child: task.isCompleted
          ? row
          : TaskSwipeRow(
              key: ValueKey('tasks.swipe.${task.id}'),
              open: _revealedTaskId == task.id,
              onOpenChanged: (open) {
                final next = open ? task.id : null;
                if (_revealedTaskId != next) {
                  setState(() => _revealedTaskId = next);
                }
              },
              onComplete: () => _toggle(task),
              onPostpone: () => _postpone(task),
              onMore: () => _open(task),
              child: row,
            ),
    );
  }

  Widget _taskRow(
    Task task, {
    double verticalPadding = SlowlightSpacing.xs,
    bool selected = false,
    bool compactMobile = false,
    bool lastMobile = false,
  }) {
    final theme = Theme.of(context);
    String? listName = task.list?.name;
    if (listName == null) {
      for (final list in _lists) {
        if (list.id == task.listId) {
          listName = list.name;
          break;
        }
      }
    }
    final meta = <String>[
      if ((listName ?? '').trim().isNotEmpty) listName!,
      if (!task.isCompleted && task.dueDate != null)
        _sameDay(task.dueDate!, DateTime.now())
            ? '今天${task.dueTime == null || task.dueTime!.isEmpty ? '' : ' ${task.dueTime}'}'
            : '${task.dueDate!.month}/${task.dueDate!.day}${task.dueTime == null || task.dueTime!.isEmpty ? '' : ' ${task.dueTime}'}',
      if (!task.isCompleted &&
          task.dueDate == null &&
          task.dueTime != null &&
          task.dueTime!.isNotEmpty)
        task.dueTime!,
      if (task.isCompleted && task.completedAt != null)
        '${_two(task.completedAt!.hour)}:${_two(task.completedAt!.minute)} 完成',
      // The task prototype retains priority semantics in row metadata on
      // Android, where there is no desktop-only colored priority stripe.
      if (task.priority == 'urgent_important' || task.priority == 'high')
        '重要 · 紧急',
      if (task.priority == 'important') '重要 · 不紧急',
      if (task.priority == 'urgent') '不重要 · 紧急',
    ];
    final largeText =
        MediaQuery.textScalerOf(
          context,
        ).scale(SlowlightTypography.secondarySize) >=
        SlowlightTypography.secondarySize * 1.3;

    return FxInkWell(
      key: ValueKey('tasks.row.${task.id}'),
      borderRadius: BorderRadius.circular(SlowlightRadius.md),
      onTap: () => _open(task),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: 4),
        decoration: BoxDecoration(
          color:
              selected
                  ? theme.colorScheme.primary.withValues(alpha: .07)
                  : null,
          borderRadius: BorderRadius.circular(SlowlightRadius.md),
          border: Border(
            bottom: lastMobile
                ? BorderSide.none
                : BorderSide(color: fxSubtleSurface(context)),
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: compactMobile ? 48 : 0),
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (!compactMobile) ...[
              Container(
                width: 3,
                height: 42,
                decoration: BoxDecoration(
                  color: task.priority == 'none'
                      ? Colors.transparent
                      : AppTheme.priorityColor(task.priority),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
            ],
            FxInkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _toggle(task),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          task.isCompleted
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                      border: Border.all(
                        color:
                            task.isCompleted
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                        width: 1.5,
                      ),
                    ),
                    child:
                        task.isCompleted
                            ? const Icon(
                              Icons.check,
                              size: 11,
                              color: Colors.white,
                            )
                            : null,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: largeText ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: SlowlightTypography.secondary(context).copyWith(
                      fontWeight: FontWeight.w500,
                      decoration:
                          task.isCompleted ? TextDecoration.lineThrough : null,
                      color:
                          task.isCompleted
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.onSurface,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta.join(' · '),
                      maxLines: largeText ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: SlowlightTypography.caption(
                        context,
                      ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            if (!compactMobile && !task.isCompleted && task.taskType == 'ongoing')
              FxChip(
                label: '进行中',
                backgroundColor: activePalette.accent.withValues(alpha: .12),
                foregroundColor: activePalette.accent,
                borderRadius: SlowlightRadius.pill,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              ),
            if (compactMobile)
              Icon(
                LucideIcons.chevronRight,
                size: SlowlightIconSize.sm,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
        ),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  String _two(int value) => value.toString().padLeft(2, '0');
}
