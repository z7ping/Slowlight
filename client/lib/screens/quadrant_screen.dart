import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/task.dart';
import '../models/todo_list.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/task_detail_sheet.dart';

typedef QuadrantData = ({
  List<Task> tasks,
  List<TodoList> lists,
});

class QuadrantScreen extends StatefulWidget {
  final Future<QuadrantData> Function()? dataLoader;
  final int refreshTick;

  const QuadrantScreen({super.key, this.dataLoader, this.refreshTick = 0});

  @override
  State<QuadrantScreen> createState() => _QuadrantScreenState();
}

class _QuadrantScreenState extends State<QuadrantScreen> {
  bool _loading = true;
  bool _hasLoadedData = false;
  bool _initialLoadFailed = false;
  int _loadVersion = 0;
  List<Task> _tasks = const [];
  List<TodoList> _lists = const [];
  String? _dragTarget;
  bool _moveHintRequested = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant QuadrantScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick == widget.refreshTick) return;
    final revision = widget.refreshTick;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.refreshTick == revision) _load();
    });
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    // A refresh must not replace the confirmed quadrant grid with a spinner.
    if (mounted) setState(() => _loading = !_hasLoadedData);
    try {
      final values = await (widget.dataLoader?.call() ?? _loadDefault());
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _tasks = values.tasks
            .where((task) => !task.isCompleted)
            .toList(growable: false);
        _lists = values.lists;
        _loading = false;
        _hasLoadedData = true;
        _initialLoadFailed = false;
      });
      if (_tasks.isNotEmpty) _showMoveHintOnce();
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _loading = false;
        _initialLoadFailed = !_hasLoadedData;
      });
      if (_hasLoadedData) {
        FxNotice.showContent(context, const Text('刷新失败，仍显示上次加载的任务'));
      }
    }
  }

  // Show the established move gesture once per device class, without
  // reserving permanent space in the four-quadrant workspace.
  void _showMoveHintOnce() {
    if (_moveHintRequested) return;
    _moveHintRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final desktop = ResponsiveLayout.isDesktopOrWider(context);
      final key = desktop
          ? 'quadrant_move_hint_desktop_v1'
          : 'quadrant_move_hint_mobile_v1';
      try {
        final preferences = await SharedPreferences.getInstance();
        if (!mounted || preferences.getBool(key) == true) return;
        FxNotice.show(
          context,
          desktop
              ? '拖拽任务移动象限，也可右键或按 Shift+F10'
              : '长按任务可移动到其他象限',
        );
        await preferences.setBool(key, true);
      } catch (_) {
        // Missing local preferences must never block the quadrant board.
      }
    });
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
    if (_loading && !_hasLoadedData) {
      return const Center(child: FxCircularProgress());
    }
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
            textScale < 1.3;
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
          final minCardHeight = textScale > 1.1 ? 324.0 : 300.0;
          final cardHeight = constraints.hasBoundedHeight
              ? math.max(
                  minCardHeight,
                  (constraints.maxHeight - padding * 2 - gap) / 2,
                )
              : minCardHeight;
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
    final previewCount = desktop ? 4 : 2;
    final emptyState = Center(
      child: desktop
          ? Text(
              '这里暂时没有任务',
              textAlign: TextAlign.center,
              style: SlowlightTypography.caption(context)
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          : FxButton(
              key: ValueKey('quadrant-add-$priority'),
              label: '添加任务',
              icon: LucideIcons.plus,
              variant: FxButtonVariant.ghost,
              onPressed: () => _addTask(priority),
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
              if (desktop || items.isNotEmpty) ...[
                const SizedBox(width: 4),
                FxIconButton(
                  tooltip: '在$title添加任务',
                  onPressed: () => _addTask(priority),
                  icon: LucideIcons.plus,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            desktop || compactMobileGrid
                ? Expanded(child: emptyState)
                : SizedBox(height: 96, child: emptyState)
          else
            ...items.take(previewCount).map(
                  (task) => desktop
                      ? _draggableTask(task, color)
                      : _taskLine(
                          task,
                          color,
                          desktop: false,
                          compact: compactMobileGrid,
                        ),
                ),
          if (items.length > previewCount)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FxButton(
                label: compactMobileGrid ? '查看全部' : '查看全部（${items.length}）',
                size: FxButtonSize.sm,
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
    // Use the existing full-list view on both platforms so desktop cards
    // never silently hide the fifth and following tasks.
    Widget content(BuildContext dialogContext) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$title · ${items.length} 项任务',
                style: SlowlightTypography.sectionTitle(dialogContext),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: math.min(
                  MediaQuery.sizeOf(dialogContext).height * .6,
                  math.max(64.0, items.length * 64.0),
                ),
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final task = items[index];
                    void open() => Navigator.of(dialogContext)
                        .pop((task: task, move: false));
                    void move() => Navigator.of(dialogContext)
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
        );
    final desktop = ResponsiveLayout.isDesktopOrWider(context);
    final selection = desktop
        ? await FxDialog.show<({Task task, bool move})>(
            context: context,
            width: 480,
            child: Builder(builder: content),
          )
        : await FxSheet.show<({Task task, bool move})>(
            context: context,
            useSafeArea: true,
            isScrollControlled: true,
            builder: content,
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
    final row = FxInkWell(
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
              if (!desktop && !compact)
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
    // Keep primary click/Enter on the existing task detail. Keyboard menu
    // keys and secondary click only expose the existing move-and-save flow.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.contextMenu):
            () => _showMoveSheet(task),
        const SingleActivator(LogicalKeyboardKey.f10, shift: true):
            () => _showMoveSheet(task),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (_) => _showMoveSheet(task),
        child: row,
      ),
    );
  }

  void _openTask(Task task) {
    TaskDetailSheet.show(context, task: task, lists: _lists, onChanged: _load);
  }

  Future<void> _addTask(String priority) {
    return TaskDetailSheet.showCreate(
      context,
      lists: _lists.isEmpty ? null : _lists,
      initialPriority: priority,
      defaultDueToday: false,
      onChanged: _load,
    );
  }

  Future<void> _showMoveSheet(Task task) async {
    // All secondary actions share one four-choice selector and the same
    // unsaved TaskDetailSheet priority draft. Only explicit Save writes.
    Widget choices(BuildContext sheetContext) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '「${task.title}」移动到…',
                style: SlowlightTypography.secondary(sheetContext)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _moveOption(sheetContext, '重要 · 紧急', 'urgent_important', task.priority),
              _moveOption(sheetContext, '重要 · 不紧急', 'important', task.priority),
              _moveOption(sheetContext, '不重要 · 紧急', 'urgent', task.priority),
              _moveOption(sheetContext, '不重要 · 不紧急', 'none', task.priority),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FxButton(
                  label: '取消',
                  variant: FxButtonVariant.ghost,
                  onPressed: () => Navigator.pop(sheetContext),
                ),
              ),
            ],
          ),
        );
    final desktop = ResponsiveLayout.isDesktopOrWider(context);
    final result = desktop
        ? await FxDialog.show<String>(
            context: context,
            width: 360,
            showCloseButton: false,
            child: Builder(builder: choices),
          )
        : await FxSheet.show<String>(
            context: context,
            useSafeArea: true,
            isScrollControlled: true,
            showDragHandle: true,
            showCloseButton: false,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(SlowlightRadius.xl),
              ),
            ),
            builder: choices,
          );
    if (result == null || result == task.priority || !mounted) return;
    await TaskDetailSheet.show(
      context,
      task: task,
      lists: _lists,
      initialPriority: result,
      onChanged: _load,
    );
  }

  Widget _moveOption(
    BuildContext selectorContext,
    String label,
    String value,
    String current,
  ) {
    final selected = value == current;
    return FxInkWell(
      borderRadius: BorderRadius.circular(SlowlightRadius.md),
      onTap: () => Navigator.pop(selectorContext, value),
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
