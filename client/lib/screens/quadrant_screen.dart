import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/task.dart';
import '../models/todo_list.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/task_detail_sheet.dart';
import 'task_create_sheet.dart';

typedef QuadrantData = ({
  List<Task> tasks,
  List<TodoList> lists,
});

class QuadrantScreen extends StatefulWidget {
  final Future<QuadrantData> Function()? dataLoader;

  const QuadrantScreen({super.key, this.dataLoader});

  @override
  State<QuadrantScreen> createState() => _QuadrantScreenState();
}

class _QuadrantScreenState extends State<QuadrantScreen> {
  bool _loading = true;
  bool _hasLoadedData = false;
  bool _initialLoadFailed = false;
  List<Task> _tasks = const [];
  List<TodoList> _lists = const [];
  String? _dragTarget;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final values = await (widget.dataLoader?.call() ?? _loadDefault());
      if (!mounted) return;
      setState(() {
        _tasks = values.tasks
            .where((task) => !task.isCompleted)
            .toList(growable: false);
        _lists = values.lists;
        _loading = false;
        _hasLoadedData = true;
        _initialLoadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialLoadFailed = !_hasLoadedData;
      });
      if (_hasLoadedData) {
        FxNotice.showContent(context, const Text('刷新失败，仍显示上次加载的任务'));
      }
    }
  }

  Future<QuadrantData> _loadDefault() async {
    final data = DataService();
    final values = await Future.wait<dynamic>([
      data.getAllTasks(),
      data.getLists(),
    ]);
    return (
      tasks: values[0] as List<Task>,
      lists: values[1] as List<TodoList>,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: FxCircularProgress());
    if (_initialLoadFailed) {
      return Center(
        child: SingleChildScrollView(
          child: FxEmptyState(
            key: const ValueKey('quadrant-load-error'),
            icon: LucideIcons.triangleAlert,
            title: '暂时无法加载四象限',
            subtitle: '任务或清单读取失败，请检查数据服务后重试。',
            action: FxButton(
              label: '重新加载',
              onPressed: _load,
            ),
          ),
        ),
      );
    }
    final desktop = ResponsiveLayout.isDesktopOrWider(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 窄屏仍沿用 Windows 的 2×2 四格；文字放大导致内容不可读时降一列。
        final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final mobileGrid = !desktop &&
            constraints.maxWidth >= 320 &&
            !(textScale >= 1.3 && constraints.maxWidth < 430);
        final cells = [
          _quadrant(
            '重要 · 紧急',
            'urgent_important',
            AppTheme.priorityUrgentImportant,
            desktop,
            compactMobileGrid: mobileGrid,
          ),
          _quadrant(
            '重要 · 不紧急',
            'important',
            AppTheme.priorityImportant,
            desktop,
            compactMobileGrid: mobileGrid,
          ),
          _quadrant(
            '不重要 · 紧急',
            'urgent',
            AppTheme.priorityUrgent,
            desktop,
            compactMobileGrid: mobileGrid,
          ),
          _quadrant(
            '不重要 · 不紧急',
            'none',
            Theme.of(context).colorScheme.outlineVariant,
            desktop,
            compactMobileGrid: mobileGrid,
          ),
        ];
        if (desktop && constraints.hasBoundedHeight) {
          const padding = 20.0;
          const gap = 12.0;
          final cellWidth = (constraints.maxWidth - padding * 2 - gap) / 2;
          final cellHeight = (constraints.maxHeight - padding * 2 - gap) / 2;
          return FxRefresh(
            onRefresh: _load,
            child: GridView.count(
              padding: const EdgeInsets.all(padding),
              crossAxisCount: 2,
              crossAxisSpacing: gap,
              mainAxisSpacing: gap,
              childAspectRatio: cellWidth / cellHeight,
              children: cells,
            ),
          );
        }
        if (mobileGrid) {
          const padding = 12.0;
          const gap = 12.0;
          final cardHeight = textScale > 1.1 ? 324.0 : 300.0;
          final width = (constraints.maxWidth - 2 * padding - gap) / 2;
          return FxRefresh(
            onRefresh: _load,
            child: GridView.count(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(padding),
              crossAxisCount: 2,
              crossAxisSpacing: gap,
              mainAxisSpacing: gap,
              childAspectRatio: width / cardHeight,
              children: cells,
            ),
          );
        }
        return FxRefresh(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: cells
                .expand((cell) => [cell, const SizedBox(height: 12)])
                .toList(),
          ),
        );
      },
    );
  }

  Widget _quadrant(
    String title,
    String priority,
    Color color,
    bool desktop, {
    bool compactMobileGrid = false,
  }) {
    final theme = Theme.of(context);
    final items = _tasks.where((task) => task.priority == priority).toList();
    final hovering = _dragTarget == priority;
    final emptyState = Center(
      child: Text(
        '这里暂时没有任务',
        textAlign: TextAlign.center,
        style: SlowlightTypography.caption(
          context,
        ).copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );

    Widget card = FxCard(
      padding: EdgeInsets.all(compactMobileGrid ? 12 : 16),
      color: fxSurface(context),
      borderRadius: SlowlightRadius.lg,
      border: Border.all(
        color: hovering
            ? Colors.transparent
            : color.withValues(alpha: priority == 'none' ? 1 : .36),
      ),
      boxShadow:
          theme.brightness == Brightness.light ? AppTheme.cardShadow : null,
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: desktop
                    ? Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: SlowlightTypography.cardTitle(context)
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _quadrantCount(items.length),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            softWrap: true,
                            style: SlowlightTypography.cardTitle(context)
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          _quadrantCount(items.length),
                        ],
                      ),
              ),
              const SizedBox(width: 4),
              FxIconButton(
                tooltip: '在$title添加任务',
                onPressed: () => _addTask(priority),
                icon: LucideIcons.plus,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            desktop || compactMobileGrid
                ? Expanded(child: emptyState)
                : SizedBox(height: 96, child: emptyState)
          else
            ...items.take(desktop ? 5 : 2).map(
                  (task) => desktop
                      ? _draggableTask(task, color)
                      : _taskLine(
                          task,
                          color,
                          desktop: false,
                          compact: compactMobileGrid,
                        ),
                ),
          if (!desktop && items.length > 2)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FxButton(
                label: '查看全部（${items.length}）',
                variant: FxButtonVariant.ghost,
                onPressed: () => _showAllTasks(title, items),
              ),
            ),
        ],
      ),
    );

    if (hovering) {
      card = CustomPaint(
        painter: _QuadrantDashedPainter(
          color: color.withValues(alpha: .8),
          radius: SlowlightRadius.lg,
        ),
        child: card,
      );
    }

    if (!desktop) return card;
    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) {
        if (details.data.priority == priority) return false;
        setState(() => _dragTarget = priority);
        return true;
      },
      onLeave: (_) {
        if (_dragTarget == priority) setState(() => _dragTarget = null);
      },
      onAcceptWithDetails: (details) {
        setState(() => _dragTarget = null);
        _moveTask(details.data, priority);
      },
      builder: (context, candidateData, rejectedData) => card,
    );
  }

  Widget _quadrantCount(int count) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: fxSubtleSurface(context),
        borderRadius: BorderRadius.circular(SlowlightRadius.pill),
      ),
      child: Text(
        '$count',
        style: SlowlightTypography.caption(context).copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Future<void> _showAllTasks(String title, List<Task> items) async {
    final selection = await FxSheet.show<({Task task, bool move})>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title · ${items.length} 项任务',
              style: SlowlightTypography.sectionTitle(sheetContext),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: math.min(
                MediaQuery.sizeOf(sheetContext).height * .6,
                math.max(64.0, items.length * 64.0),
              ),
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final task = items[index];
                  void open() => Navigator.of(sheetContext)
                      .pop((task: task, move: false));
                  void move() => Navigator.of(sheetContext)
                      .pop((task: task, move: true));
                  return _taskLine(
                    task,
                    AppTheme.priorityColor(task.priority),
                    desktop: false,
                    onTap: open,
                    onMove: move,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selection == null) return;
    if (selection.move) {
      await _showMoveSheet(selection.task);
    } else {
      _openTask(selection.task);
    }
  }

  Widget _draggableTask(Task task, Color color) {
    final theme = Theme.of(context);
    return LongPressDraggable<Task>(
      data: task,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: FxCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: fxSurface(context),
            borderRadius: SlowlightRadius.lg,
            border: Border.all(color: fxBorder(context)),
            boxShadow: theme.brightness == Brightness.light
                ? AppTheme.cardShadow
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '●',
                  style: TextStyle(
                    color: color,
                    fontSize: SlowlightTypography.captionSize,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SlowlightTypography.secondary(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: .35,
        child: _taskLine(task, color, desktop: true),
      ),
      child: _taskLine(task, color, desktop: true),
    );
  }

  Widget _taskLine(
    Task task,
    Color color, {
    required bool desktop,
    bool compact = false,
    VoidCallback? onTap,
    VoidCallback? onMove,
  }) {
    return FxInkWell(
      borderRadius: BorderRadius.circular(SlowlightRadius.md),
      // 安卓点击任务与其他任务列表一致：打开详情。
      // 移动象限使用右侧明确的“更多”操作，不隐藏在长按手势里。
      onTap: onTap ?? () => _openTask(task),
      onLongPress: desktop ? null : (onMove ?? () => _showMoveSheet(task)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: SlowlightControlSize.minTouchTarget,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 2 : 7, horizontal: 2),
          child: Row(
            children: [
              Text(
                '●',
                style: TextStyle(
                  color: color,
                  fontSize: SlowlightTypography.captionSize,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.title,
                  maxLines: compact ||
                          MediaQuery.textScalerOf(context).scale(
                                SlowlightTypography.secondarySize,
                              ) >=
                              SlowlightTypography.secondarySize * 1.3
                      ? 2
                      : 1,
                  overflow: TextOverflow.ellipsis,
                  style: SlowlightTypography.secondary(context),
                ),
              ),
              if (!desktop)
                FxIconButton(
                  icon: LucideIcons.ellipsis,
                  tooltip: '移动到其他象限',
                  iconSize: SlowlightIconSize.md,
                  onPressed: onMove ?? () => _showMoveSheet(task),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openTask(Task task) {
    TaskDetailSheet.show(context, task: task, lists: _lists, onChanged: _load);
  }

  Future<void> _addTask(String priority) {
    return TaskCreateSheet.showQuickCreate(
      context,
      initialPriority: priority,
      defaultDueToday: false,
      onCreated: _load,
    );
  }

  Future<void> _showMoveSheet(Task task) async {
    final result = await FxSheet.show<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SlowlightRadius.xl),
        ),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '「${task.title}」移动到…',
              style: SlowlightTypography.secondary(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _moveOption('重要 · 紧急', 'urgent_important', task.priority),
            _moveOption('重要 · 不紧急', 'important', task.priority),
            _moveOption('不重要 · 紧急', 'urgent', task.priority),
            _moveOption('不重要 · 不紧急', 'none', task.priority),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FxButton(
                label: '取消',
                variant: FxButtonVariant.ghost,
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
    if (result == null || result == task.priority) return;
    await _moveTask(task, result);
  }

  Widget _moveOption(String label, String value, String current) {
    final selected = value == current;
    return FxInkWell(
      borderRadius: BorderRadius.circular(SlowlightRadius.md),
      onTap: () => Navigator.pop(context, value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.flag,
                size: SlowlightIconSize.md,
                color: AppTheme.priorityColor(value),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: SlowlightTypography.secondary(context),
                ),
              ),
              if (selected)
                FxChip(
                  label: '当前',
                  backgroundColor: activePalette.accent.withValues(alpha: .12),
                  foregroundColor: activePalette.accent,
                  borderRadius: SlowlightRadius.pill,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _moveTask(Task task, String priority) async {
    try {
      await DataService().updateTask(
        localId: task.id,
        listId: task.listId,
        title: task.title,
        description: task.description,
        priority: priority,
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
      if (mounted) {
        FxNotice.showContent(context, Text('任务已移动'));
      }
      await _load();
    } catch (_) {
      if (!mounted) return;
      FxNotice.showContent(context, Text('移动任务失败'));
    }
  }
}

class _QuadrantDashedPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _QuadrantDashedPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + 6, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QuadrantDashedPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
