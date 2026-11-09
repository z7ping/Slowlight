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
  /// Optional seam for testing completion without writing a real account.
  final Future<Task> Function(Task task)? taskCompleter;
  final int refreshTick;

  const QuadrantScreen({
    super.key,
    this.dataLoader,
    this.taskCompleter,
    this.refreshTick = 0,
  });

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
  bool _lastRefreshFailed = false;
  String _selectedPriority = 'urgent_important';
  final Set<int> _completingTaskIds = <int>{};

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
        _lastRefreshFailed = false;
      });
      if (_tasks.isNotEmpty) _showMoveHintOnce();
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _loading = false;
        _initialLoadFailed = !_hasLoadedData;
        _lastRefreshFailed = true;
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
          // Same responsive 2x2 viewport fill as product-internal:
          // no fixed 300dp card, no unnecessary top summary.
          const padding = 12.0;
          const gap = 9.0;
          const bottomRoom = 40.0;
          const minimumCardHeight = 205.0;
          final cardHeight = constraints.hasBoundedHeight
              ? math.max(
                  minimumCardHeight,
                  (constraints.maxHeight - padding - bottomRoom - gap) / 2,
                )
              : minimumCardHeight;
          final width = (constraints.maxWidth - padding * 2 - gap) / 2;
          return _mobileBoard(
            FxRefresh(
              onRefresh: _load,
              child: GridView.count(
                key: const ValueKey('quadrant-mobile-grid'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(padding, padding, padding, bottomRoom),
                crossAxisCount: 2,
                crossAxisSpacing: gap,
                mainAxisSpacing: gap,
                childAspectRatio: width / cardHeight,
                children: cells,
              ),
            ),
          );
        }
        if (!desktop) {
          // Large text keeps four complete cards in one scrolling column.
          final cardHeight = textScale >= 1.9
              ? 332.0
              : textScale >= 1.3
                  ? 238.0
                  : 210.0;
          return _mobileBoard(
            FxRefresh(
              onRefresh: _load,
              child: ListView(
                key: const ValueKey('quadrant-mobile-list'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                children: [
                  for (final cell in cells)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: SizedBox(height: cardHeight, child: cell),
                    ),
                ],
              ),
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

  Widget _mobileBoard(Widget scrollable) {
    final colors = Theme.of(context).colorScheme;
    final label = switch (_selectedPriority) {
      'urgent_important' => '重要 · 紧急',
      'important' => '重要 · 不紧急',
      'urgent' => '不重要 · 紧急',
      _ => '不重要 · 不紧急',
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        scrollable,
        Positioned(
          left: 14,
          right: 76,
          bottom: 9,
          child: Text(
            '点击象限选中 · 长按任务移动',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SlowlightTypography.caption(context).copyWith(
              color: colors.onSurfaceVariant,
              fontSize: SlowlightTypography.resolvedCaptionSize * .88,
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Semantics(
            label: '在$label添加任务',
            button: true,
            child: Material(
              color: colors.primary,
              borderRadius: BorderRadius.circular(SlowlightRadius.lg),
              elevation: 4,
              child: FxInkWell(
                key: const ValueKey('quadrant-add'),
                borderRadius: BorderRadius.circular(SlowlightRadius.lg),
                onTap: () => _addTask(_selectedPriority),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(LucideIcons.plus,
                      size: 22, color: colors.onPrimary),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _mobileQuadrant(
    String title,
    String priority,
    Color color,
    List<Task> items, {
    required bool compact,
  }) {
    final colors = Theme.of(context).colorScheme;
    final selected = _selectedPriority == priority;
    final preview = items.length > 3 ? 2 : 3;
    final titleStyle = SlowlightTypography.caption(context).copyWith(
      fontWeight: FontWeight.w700,
      color: colors.onSurface,
    );

    return FxCard(
      key: ValueKey('quadrant-card-$priority'),
      onTap: () {
        if (_selectedPriority != priority) {
          setState(() => _selectedPriority = priority);
        }
      },
      padding: EdgeInsets.zero,
      color: selected
          ? Color.alphaBlend(
              colors.primary.withValues(alpha: .035),
              fxSurface(context),
            )
          : fxSurface(context),
      borderRadius: SlowlightRadius.lg,
      border: Border.all(
        color: selected
            ? colors.primary.withValues(alpha: .52)
            : colors.outlineVariant,
      ),
      expanded: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A slim semantic edge, rather than four heavy colored borders.
          Container(width: 3, color: color),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    selected: selected,
                    label: '选择$title象限，共${items.length}项任务',
                    button: true,
                    child: FxInkWell(
                      onTap: () {
                        if (_selectedPriority != priority) {
                          setState(() => _selectedPriority = priority);
                        }
                      },
                      child: SizedBox(
                        height: 38,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: titleStyle,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${items.length} 项',
                              style: SlowlightTypography.caption(context)
                                  .copyWith(
                                color: colors.onSurfaceVariant,
                                fontSize:
                                    SlowlightTypography.resolvedCaptionSize * .92,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  FxSeparator.horizontal(
                    height: 1,
                    thickness: 1,
                    color: colors.outlineVariant,
                  ),
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Text(
                              '暂无任务',
                              style: SlowlightTypography.caption(context)
                                  .copyWith(color: colors.onSurfaceVariant),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final task in items.take(preview))
                                _taskLine(
                                  task,
                                  color,
                                  desktop: false,
                                  compact: compact,
                                  quadrantPreview: true,
                                ),
                              if (items.length > preview)
                                FxInkWell(
                                  key: ValueKey('quadrant-more-$priority'),
                                  onTap: () => _showAllTasks(title, items),
                                  child: SizedBox(
                                    height: 36,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '还有 ${items.length - preview} 项 · 查看全部',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            SlowlightTypography.caption(context)
                                                .copyWith(
                                          color: colors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
    if (!desktop) {
      return _mobileQuadrant(
        title, priority, color, items,
        compact: compactMobileGrid,
      );
    }
    final hovering = _dragTarget == priority;
    Widget card = FxCard(
      padding: const EdgeInsets.all(16),
      color: fxSurface(context),
      borderRadius: SlowlightRadius.lg,
      border: Border.all(
        color: hovering ? Colors.transparent : color.withValues(alpha: .36),
      ),
      boxShadow: theme.brightness == Brightness.light
          ? AppTheme.cardShadow
          : null,
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
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
                ),
              ),
              FxIconButton(
                tooltip: '在$title添加任务',
                onPressed: () => _addTask(priority),
                icon: LucideIcons.plus,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  '这里暂时没有任务',
                  textAlign: TextAlign.center,
                  style: SlowlightTypography.caption(context)
                      .copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            ...items.take(4).map((task) => _draggableTask(task, color)),
          if (items.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FxButton(
                label: '查看全部（${items.length}）',
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

  Widget _taskCompleteControl(Task task) {
    final pending = _completingTaskIds.contains(task.id);
    return Semantics(
      label: '完成${task.title}',
      button: true,
      enabled: !pending,
      child: FxInkWell(
        key: ValueKey('quadrant-complete-${task.id}'),
        // Keep the gesture recognizer while pending; otherwise the tap would
        // fall through to the parent task row and unexpectedly open its editor.
        onTap: () {
          if (!pending) _completeTask(task);
        },
        enableFeedback: !pending,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Opacity(
              opacity: pending ? .45 : 1,
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: FxCheckbox(
                    value: false,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _taskLine(
    Task task,
    Color color, {
    required bool desktop,
    bool compact = false,
    bool quadrantPreview = false,
    VoidCallback? onTap,
    VoidCallback? onMove,
  }) {
    final row = FxInkWell(
      borderRadius: BorderRadius.circular(SlowlightRadius.md),
      // Primary tap opens the existing editor; long press/keyboard-menu
      // still opens the established move-and-save flow.
      onTap: onTap ?? () => _openTask(task),
      onLongPress: desktop ? null : (onMove ?? () => _showMoveSheet(task)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: quadrantPreview
              ? MediaQuery.textScalerOf(context).scale(16) >= 30
                  ? 88
                  : MediaQuery.textScalerOf(context).scale(16) >= 21
                      ? 56
                      : SlowlightControlSize.minTouchTarget
              : SlowlightControlSize.minTouchTarget,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: quadrantPreview ? 0 : (compact ? 2 : 7),
            horizontal: quadrantPreview ? 0 : 2,
          ),
          child: Row(
            children: [
              if (quadrantPreview)
                _taskCompleteControl(task)
              else ...[
                Text(
                  '●',
                  style: TextStyle(
                    color: color,
                    fontSize: SlowlightTypography.captionSize,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  task.title,
                  maxLines: quadrantPreview || compact ||
                          MediaQuery.textScalerOf(context).scale(
                                SlowlightTypography.secondarySize,
                              ) >=
                              SlowlightTypography.secondarySize * 1.3
                      ? 2
                      : 1,
                  overflow: TextOverflow.ellipsis,
                  style: quadrantPreview && compact
                      ? SlowlightTypography.caption(context).copyWith(
                          fontSize: SlowlightTypography.resolvedCaptionSize * .95,
                        )
                      : SlowlightTypography.secondary(context),
                ),
              ),
              if (!desktop && !compact && !quadrantPreview)
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

  Future<void> _completeTask(Task task) async {
    // Cloud completion may be a stateful toggle. Never retry against a stale
    // task list, and never show success before a fresh list confirms it.
    if (_lastRefreshFailed) {
      FxNotice.show(context, '任务列表刷新未确认，请先刷新再操作');
      return;
    }
    if (!_completingTaskIds.add(task.id)) return;
    if (mounted) setState(() {});
    HapticFeedback.lightImpact();
    try {
      final result = await (widget.taskCompleter?.call(task) ??
          DataService().setTaskCompletion(
            task.id,
            null,
            completed: true,
            expectedCompleted: false,
          ));
      if (!mounted) return;
      if (!result.isCompleted) {
        await _load();
        if (mounted) FxNotice.show(context, '任务状态已变化，请核对后再操作');
        return;
      }
      await _load();
      if (!mounted) return;
      if (_lastRefreshFailed || _tasks.any((item) => item.id == task.id)) {
        FxNotice.show(context, '任务更新结果未核实，请刷新后核对');
        return;
      }
      FxNotice.show(
        context,
        '任务已完成',
        variant: FxNoticeVariant.success,
        duration: const Duration(seconds: 8),
        action: task.isRepeat || result.completedAt == null
            ? null
            : FxNoticeAction(
                label: '撤销',
                onPressed: () => _undoCompletion(
                  task.id, expectedCompletedAt: result.completedAt!,
                ),
              ),
      );
    } on StateError {
      await _load();
      if (mounted) FxNotice.show(context, '任务状态已变化，请核对后再操作');
    } catch (_) {
      // A timeout may occur after the backend wrote the completion.
      // Refresh first instead of issuing a potentially destructive retry.
      await _load();
      if (mounted) FxNotice.show(context, '任务结果未确认，请核对任务状态');
    } finally {
      _completingTaskIds.remove(task.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _undoCompletion(
    int taskId, {
    required DateTime expectedCompletedAt,
  }) async {
    if (!_completingTaskIds.add(taskId)) return;
    try {
      final tasks = await DataService().getAllTasks();
      final current = tasks.cast<Task?>().firstWhere(
        (task) => task?.id == taskId,
        orElse: () => null,
      );
      if (!mounted) return;
      if (current == null || current.isRepeat || !current.isCompleted ||
          current.completedAt == null ||
          !current.completedAt!.isAtSameMomentAs(expectedCompletedAt)) {
        FxNotice.show(context, '任务完成记录已变化，未执行旧撤销');
        return;
      }
      final updated = await DataService().setTaskCompletion(
        taskId,
        null,
        completed: false,
        expectedCompleted: true,
        expectedCompletedAt: expectedCompletedAt,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      if (updated.isCompleted ||
          _lastRefreshFailed ||
          !_tasks.any((task) => task.id == taskId)) {
        FxNotice.show(context, '撤销结果尚未确认，请刷新核对');
        return;
      }
      FxNotice.show(context, '已恢复待办');
    } on StateError {
      await _load();
      if (mounted) FxNotice.show(context, '任务状态已变化，未执行旧撤销');
    } catch (_) {
      FxNotice.show(context, '撤销结果未确认，请核对任务状态');
    } finally {
      _completingTaskIds.remove(taskId);
    }
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
