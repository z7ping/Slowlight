import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/task.dart';
import '../models/todo_list.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../widgets/high_fidelity/high_fidelity_ui.dart';
import '../widgets/task_detail_sheet.dart';
import 'task_create_sheet.dart';

class QuadrantScreen extends StatefulWidget {
  const QuadrantScreen({super.key});

  @override
  State<QuadrantScreen> createState() => _QuadrantScreenState();
}

class _QuadrantScreenState extends State<QuadrantScreen> {
  bool _loading = true;
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
      final data = DataService();
      final values = await Future.wait<dynamic>([
        data.getAllTasks(),
        data.getLists(),
      ]);
      if (!mounted) return;
      setState(() {
        _tasks = (values[0] as List<Task>)
            .where((task) => !task.isCompleted)
            .toList(growable: false);
        _lists = values[1] as List<TodoList>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final desktop = MediaQuery.sizeOf(context).width >= 1024;
    final cells = [
      _quadrant(
        '重要 · 紧急',
        'urgent_important',
        AppTheme.priorityUrgentImportant,
        desktop,
      ),
      _quadrant(
        '重要 · 不紧急',
        'important',
        AppTheme.priorityImportant,
        desktop,
      ),
      _quadrant(
        '不重要 · 紧急',
        'urgent',
        AppTheme.priorityUrgent,
        desktop,
      ),
      _quadrant(
        '不重要 · 不紧急',
        'none',
        Theme.of(context).colorScheme.outlineVariant,
        desktop,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (desktop && constraints.hasBoundedHeight) {
          const padding = 20.0;
          const gap = 12.0;
          final cellWidth = (constraints.maxWidth - padding * 2 - gap) / 2;
          final cellHeight = (constraints.maxHeight - padding * 2 - gap) / 2;
          return RefreshIndicator(
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
        return RefreshIndicator(
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
    bool desktop,
  ) {
    final theme = Theme.of(context);
    final items = _tasks.where((task) => task.priority == priority).toList();
    final hovering = _dragTarget == priority;
    final emptyState = InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      onTap: () => _addTask(priority),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.plus, size: 20),
            const SizedBox(height: 5),
            Text(
              '这里暂时没有任务 · 添加任务',
              style: TextStyle(
                fontSize: AppTheme.textXs,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );

    Widget card = HfCard(
      padding: const EdgeInsets.all(16),
      border: Border.all(
        color: hovering
            ? Colors.transparent
            : color.withValues(alpha: priority == 'none' ? 1 : .36),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: hfSubtleSurface(context),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${items.length}',
                  style: TextStyle(
                    fontSize: AppTheme.textXs,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  tooltip: '在$title添加任务',
                  onPressed: () => _addTask(priority),
                  icon: const Icon(LucideIcons.plus, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            desktop
                ? Expanded(child: emptyState)
                : SizedBox(height: 96, child: emptyState)
          else
            ...items.take(5).map(
                  (task) => desktop
                      ? _draggableTask(task, color)
                      : _taskLine(task, color, desktop: false),
                ),
        ],
      ),
    );

    if (hovering) {
      card = CustomPaint(
        painter: _QuadrantDashedPainter(
          color: color.withValues(alpha: .8),
          radius: AppTheme.radiusLg,
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

  Widget _draggableTask(Task task, Color color) {
    return LongPressDraggable<Task>(
      data: task,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: HfCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('●', style: TextStyle(color: color, fontSize: 10)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: AppTheme.textSm),
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

  Widget _taskLine(Task task, Color color, {required bool desktop}) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      onTap: () => desktop ? _openTask(task) : _showMoveSheet(task),
      onLongPress: desktop ? null : () => _openTask(task),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
          child: Row(
            children: [
              Text('●', style: TextStyle(color: color, fontSize: 10)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: AppTheme.textSm),
                ),
              ),
              if (!desktop) const Icon(LucideIcons.ellipsis, size: 17),
            ],
          ),
        ),
      ),
    );
  }

  void _openTask(Task task) {
    TaskDetailSheet.show(
      context,
      task: task,
      lists: _lists,
      onChanged: _load,
    );
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
    final result = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusXl),
        ),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '「${task.title}」移动到…',
              style: const TextStyle(
                fontSize: AppTheme.textSm,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _moveOption('🔴', '重要 · 紧急', 'urgent_important', task.priority),
            _moveOption('🔵', '重要 · 不紧急', 'important', task.priority),
            _moveOption('🟠', '不重要 · 紧急', 'urgent', task.priority),
            _moveOption('🍃', '不重要 · 不紧急', 'none', task.priority),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ),
          ],
        ),
      ),
    );
    if (result == null || result == task.priority) return;
    await _moveTask(task, result);
  }

  Widget _moveOption(
    String emoji,
    String label,
    String value,
    String current,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
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
              Text(emoji),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 13)),
              ),
              if (value == current) const HfChip('当前', accent: true),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('任务已移动'),
          ),
        );
      }
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('移动任务失败'),
        ),
      );
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
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ),
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
