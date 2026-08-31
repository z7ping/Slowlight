import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/task.dart';
import '../models/todo_list.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/task_detail_sheet.dart';
import 'home_task_detail_panel.dart';
import 'task_create_sheet.dart';

class TaskToolScreen extends StatefulWidget {
  const TaskToolScreen({super.key});

  @override
  State<TaskToolScreen> createState() => _TaskToolScreenState();
}

class _TaskToolScreenState extends State<TaskToolScreen> {
  bool _loading = true;
  int _segment = 0;
  List<Task> _today = const [];
  List<Task> _all = const [];
  List<Task> _completed = const [];
  List<TodoList> _lists = const [];
  Task? _selectedTask;
  final Map<int, double> _swipeOffsets = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = DataService();
      final values = await Future.wait<dynamic>([
        data.getTodayTasks(),
        data.getAllTasks(),
        data.getCompletedTasks(),
        data.getLists(),
      ]);
      if (!mounted) return;
      setState(() {
        _today = values[0] as List<Task>;
        _all = values[1] as List<Task>;
        _completed = values[2] as List<Task>;
        _lists = values[3] as List<TodoList>;
        if (_selectedTask != null) {
          _selectedTask = _all.cast<Task?>().firstWhere(
            (task) => task?.id == _selectedTask!.id,
            orElse: () => null,
          );
        }
        _swipeOffsets.clear();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Task> get _visible => switch (_segment) {
    1 => _all,
    2 => _completed,
    _ => _today,
  };

  Widget _card({required Widget child, EdgeInsetsGeometry? padding}) {
    final theme = Theme.of(context);
    return FxCard(
      padding: padding ?? const EdgeInsets.all(16),
      color: fxSurface(context),
      borderRadius: AppTheme.radiusLg,
      border: Border.all(color: fxBorder(context)),
      boxShadow:
          theme.brightness == Brightness.light ? AppTheme.cardShadow : null,
      expanded: true,
      child: child,
    );
  }

  Widget _segments() => FxSegmented(
    labels: const ['今天', '全部', '已完成'],
    selectedIndex: _segment,
    onChanged: (index) => setState(() => _segment = index),
    backgroundColor: fxSubtleSurface(context),
    selectedColor: fxSurface(context),
    borderRadius: AppTheme.radiusMd,
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

  Future<void> _toggle(Task task) async {
    if (MediaQuery.sizeOf(context).width < 600) HapticFeedback.lightImpact();
    try {
      if (task.isCompleted) {
        await DataService().uncompleteTask(task.id, null);
      } else {
        await DataService().completeTask(task.id, null);
      }
      await _load();
    } catch (_) {
      _message('任务状态更新失败');
    }
  }

  Future<void> _postpone(Task task) async {
    if (MediaQuery.sizeOf(context).width < 600) HapticFeedback.lightImpact();
    try {
      await DataService().postponeTask(task.id, null);
      _message('已顺延到明天');
      await _load();
    } catch (_) {
      _message('顺延任务失败');
    }
  }

  void _open(Task task) {
    final availableWidth =
        context.size?.width ?? MediaQuery.sizeOf(context).width;
    if (availableWidth >= 860) {
      setState(() => _selectedTask = task);
      return;
    }
    TaskDetailSheet.show(context, task: task, lists: _lists, onChanged: _load);
  }

  Future<void> _create() async {
    if (_lists.isEmpty) {
      _message('请先创建一个清单');
      return;
    }
    final created = await TaskCreateSheet.showFullCreate(
      context,
      lists: _lists,
      selectedListId: _lists.first.id,
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
    if (_loading) return const Center(child: FxCircularProgress());
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 600;
        final desktop = constraints.maxWidth >= 860;
        return FxRefresh(
          onRefresh: _load,
          child:
              desktop
                  ? _desktopContent()
                  : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 72),
                    children: [
                      _taskActionBar(),
                      const SizedBox(height: 14),
                      _card(
                        child:
                            _visible.isEmpty
                                ? FxEmptyState(
                                  emoji: '🍃',
                                  title:
                                      _segment == 2 ? '还没有已完成任务' : '这里暂时没有任务',
                                  subtitle:
                                      _segment == 0
                                          ? '今天可以从一件真正想推进的事开始'
                                          : '切换其他筛选看看',
                                  action:
                                      _segment == 0
                                          ? FxButton(
                                            label: '新建任务',
                                            variant: FxButtonVariant.secondary,
                                            onPressed: _create,
                                          )
                                          : null,
                                )
                                : Column(
                                  children: _visible
                                      .map(
                                        (task) =>
                                            mobile
                                                ? _swipeTaskRow(task)
                                                : _taskRow(task),
                                      )
                                      .toList(growable: false),
                                ),
                      ),
                    ],
                  ),
        );
      },
    );
  }

  Widget _desktopContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        children: [
          _taskActionBar(),
          const SizedBox(height: 14),
          Expanded(
            child:
                _visible.isEmpty
                    ? _card(child: _emptyState())
                    : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 430,
                          child: _card(
                            child: ListView(
                              children: _visible
                                  .map(
                                    (task) => _taskRow(
                                      task,
                                      selected: _selectedTask?.id == task.id,
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _card(
                            padding: EdgeInsets.zero,
                            child:
                                _selectedTask == null
                                    ? _desktopEmptyDetail()
                                    : HomeTaskDetailPanel(
                                      key: ValueKey(_selectedTask!.id),
                                      task: _selectedTask!,
                                      onClose:
                                          () => setState(
                                            () => _selectedTask = null,
                                          ),
                                      onRefresh: _load,
                                    ),
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
    emoji: '🍃',
    title: _segment == 2 ? '还没有已完成任务' : '这里暂时没有任务',
    subtitle: _segment == 0 ? '今天可以从一件真正想推进的事开始' : '切换其他筛选看看',
    action:
        _segment == 0
            ? FxButton(
              label: '新建任务',
              variant: FxButtonVariant.secondary,
              onPressed: _create,
            )
            : null,
  );

  Widget _desktopEmptyDetail() {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: .08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.mousePointerClick,
                  size: 30,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                '选择一个任务查看详情',
                style: SlowlightTypography.pageTitle(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '在左侧选择任务后，可以在这里查看和编辑任务信息。',
                textAlign: TextAlign.center,
                style: SlowlightTypography.secondary(
                  context,
                ).copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 22),
              FxButton(
                label: '新建任务',
                icon: LucideIcons.plus,
                variant: FxButtonVariant.secondary,
                size: FxButtonSize.sm,
                onPressed: _create,
              ),
              const SizedBox(height: 18),
              Text(
                '提示：点击左侧任务即可在当前页面查看详情',
                textAlign: TextAlign.center,
                style: SlowlightTypography.caption(
                  context,
                ).copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _swipeTaskRow(Task task) {
    if (task.isCompleted) return _taskRow(task);
    final offset = _swipeOffsets[task.id] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: SizedBox(
          height: 62,
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 140,
                    child: Row(
                      children: [
                        Expanded(
                          child: FxInkWell(
                            onTap: () => _postpone(task),
                            child: Container(
                              color: AppTheme.warning,
                              alignment: Alignment.center,
                              child: const Text(
                                '⏱ 顺延',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: SlowlightTypography.captionSize,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: FxInkWell(
                            onTap: () => _toggle(task),
                            child: Container(
                              color: AppTheme.success,
                              alignment: Alignment.center,
                              child: const Text(
                                '✓ 完成',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: SlowlightTypography.captionSize,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                left: offset,
                right: -offset,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      final next = offset + details.delta.dx;
                      _swipeOffsets[task.id] = next.clamp(-140.0, 0.0);
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    final current = _swipeOffsets[task.id] ?? 0;
                    setState(() {
                      _swipeOffsets[task.id] = current < -48 ? -140 : 0;
                    });
                  },
                  child: Container(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    child: _taskRow(task, verticalPadding: 0),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _taskRow(
    Task task, {
    double verticalPadding = 10,
    bool selected = false,
  }) {
    final theme = Theme.of(context);
    final meta = <String>[
      if ((task.list?.name ?? '').trim().isNotEmpty) task.list!.name,
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
    ];
    final largeText =
        MediaQuery.textScalerOf(
          context,
        ).scale(SlowlightTypography.secondarySize) >=
        SlowlightTypography.secondarySize * 1.3;

    return FxInkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      onTap: () => _open(task),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: 4),
        decoration: BoxDecoration(
          color:
              selected
                  ? theme.colorScheme.primary.withValues(alpha: .07)
                  : null,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border(bottom: BorderSide(color: fxSubtleSurface(context))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 3,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.priorityColor(task.priority),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
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
                      borderRadius: BorderRadius.circular(6),
                      color:
                          task.isCompleted
                              ? AppTheme.success
                              : Colors.transparent,
                      border: Border.all(
                        color:
                            task.isCompleted
                                ? AppTheme.success
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
            if (!task.isCompleted && task.taskType == 'ongoing')
              FxChip(
                label: '进行中',
                backgroundColor: activePalette.accent.withValues(alpha: .12),
                foregroundColor: activePalette.accent,
                borderRadius: 999,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              ),
          ],
        ),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  String _two(int value) => value.toString().padLeft(2, '0');
}
