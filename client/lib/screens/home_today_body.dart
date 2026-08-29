import 'package:flutter/material.dart';
import '../models/task.dart';
import '../models/task_filter_sort.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/task_tile.dart';
import 'home_habits_section.dart';

/// 今日任务视图组件
class HomeTodayBody extends StatefulWidget {
  final List<Task> tasks;
  final List<Map<String, dynamic>> habits;
  final TaskFilterSort filterSort;
  final Set<int> selectedTaskIds;
  final bool isSelectionMode;
  final bool todayTasksExpanded;
  final bool habitsExpanded;
  final bool overdueExpanded;
  final Function(Task) onToggleTask;
  final Function(Task) onDeleteTask;
  final Function(Task) onPostponeTask;
  final Function(Task) onTapTask;
  final Function(Task) onLongPressTask;
  final VoidCallback onToggleTodayExpanded;
  final VoidCallback onToggleHabitsExpanded;
  final VoidCallback onToggleOverdueExpanded;
  final VoidCallback onRefresh;
  final Function(Task) onOpenDetailPanel;

  const HomeTodayBody({
    super.key,
    required this.tasks,
    required this.habits,
    required this.filterSort,
    required this.selectedTaskIds,
    required this.isSelectionMode,
    required this.todayTasksExpanded,
    required this.habitsExpanded,
    required this.overdueExpanded,
    required this.onToggleTask,
    required this.onDeleteTask,
    required this.onPostponeTask,
    required this.onTapTask,
    required this.onLongPressTask,
    required this.onToggleTodayExpanded,
    required this.onToggleHabitsExpanded,
    required this.onToggleOverdueExpanded,
    required this.onRefresh,
    required this.onOpenDetailPanel,
  });

  @override
  State<HomeTodayBody> createState() => _HomeTodayBodyState();
}

class _HomeTodayBodyState extends State<HomeTodayBody> {
  List<Task> get _filteredTasks =>
      widget.tasks.applyFilterSort(widget.filterSort);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 分类：今日任务（含已完成）和 延期未完成
    final todayTasks = <Task>[];
    final overdueTasks = <Task>[];

    for (final task in _filteredTasks) {
      if (task.dueDate == null) {
        todayTasks.add(task);
        continue;
      }
      final due =
          DateTime(task.dueDate!.year, task.dueDate!.month, task.dueDate!.day);
      if (due.isBefore(today) && !task.isCompleted) {
        overdueTasks.add(task);
      } else {
        todayTasks.add(task);
      }
    }

    // 今日任务内排序：未完成的排前面，已完成的排后面
    todayTasks.sort((a, b) {
      if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
      return 0;
    });

    final completedCount = todayTasks.where((t) => t.isCompleted).length;

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      color: AppTheme.primary,
      child: ListView(
        key: const PageStorageKey('today_list'),
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 92),
        children: [
          // ====== Section 1: 今日任务 (always visible, default expanded) ======
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warmGray300.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppTheme.warmBorder.withValues(alpha: 0.5),
                  width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FxInkWell(
                  onTap: widget.onToggleTodayExpanded,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: EdgeInsets.only(
                        bottom: widget.todayTasksExpanded ? 8 : 0),
                    child: Row(
                      children: [
                        Icon(Icons.wb_sunny_outlined,
                            size: 14, color: AppTheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          todayTasks.isEmpty
                              ? '今日任务'
                              : '今日任务 $completedCount/${todayTasks.length}',
                          style: TextStyle(
                            fontSize: AppTheme.textMd,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          widget.todayTasksExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 16,
                          color: AppTheme.warmGray400,
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.todayTasksExpanded) ...[
                  if (todayTasks.isNotEmpty)
                    ...todayTasks.map((task) => TaskTile(
                          key: ValueKey(task.id),
                          task: task,
                          compact: true,
                          isSelected: widget.selectedTaskIds.contains(task.id),
                          onToggle: () => widget.onToggleTask(task),
                          onDelete: () => widget.onDeleteTask(task),
                          onPostpone: () => widget.onPostponeTask(task),
                          onLongPress: () => widget.onLongPressTask(task),
                          onTap: () => widget.onTapTask(task),
                        ))
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Text('今天清闲 ☀️ 加个任务？',
                            style: TextStyle(
                                fontSize: AppTheme.textMd,
                                color: AppTheme.warmGray400,
                                height: 1.4)),
                      ),
                    ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ====== Section 2: 习惯打卡 ======
          HomeHabitsSection(
            habits: widget.habits,
            expanded: widget.habitsExpanded,
            onToggleExpanded: widget.onToggleHabitsExpanded,
            onRefresh: widget.onRefresh,
          ),

          const SizedBox(height: 12),

          // ====== Section 3: 延期任务 (always visible, default collapsed) ======
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warmGray300.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppTheme.warmBorder.withValues(alpha: 0.5),
                  width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FxInkWell(
                  onTap: widget.onToggleOverdueExpanded,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        EdgeInsets.only(bottom: widget.overdueExpanded ? 8 : 0),
                    child: Row(
                      children: [
                        Icon(Icons.history,
                            size: 14, color: AppTheme.warmGray400),
                        const SizedBox(width: 4),
                        Text(
                          '延期 ${overdueTasks.length} 项',
                          style: TextStyle(
                            fontSize: AppTheme.textMd,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.warmGray500,
                          ),
                        ),
                        const Spacer(),
                        if (overdueTasks.isNotEmpty)
                          FxInkWell(
                            onTap: () async {
                              int failed = 0;
                              for (final task in overdueTasks) {
                                try {
                                  await DataService().updateTask(
                                    localId: task.id,
                                    serverId: null,
                                    listId: task.listId ?? 1,
                                    title: task.title,
                                    description: task.description,
                                    priority: task.priority,
                                    dueDate: today,
                                    tagIds: task.tags.map((t) => t.id).toList(),
                                  );
                                } catch (_) {
                                  failed++;
                                }
                              }
                              widget.onRefresh();
                              if (mounted) {
                                final msg = failed > 0
                                    ? '顺延 ${overdueTasks.length - failed} 项完成，$failed 项失败'
                                    : '已将 ${overdueTasks.length} 个任务顺延至今天';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(msg)),
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.update,
                                      size: 14, color: AppTheme.primary),
                                  const SizedBox(width: 4),
                                  Text('顺延至今',
                                      style: TextStyle(
                                          fontSize: AppTheme.textMd,
                                          color: AppTheme.primary)),
                                ],
                              ),
                            ),
                          ),
                        if (overdueTasks.isNotEmpty) const SizedBox(width: 8),
                        Icon(
                          widget.overdueExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 16,
                          color: AppTheme.warmGray400,
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.overdueExpanded) ...[
                  if (overdueTasks.isNotEmpty)
                    ...overdueTasks.map((task) => _buildOverdueTile(task))
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          Text('无延期任务 ✨',
                              style: TextStyle(
                                  fontSize: AppTheme.textMd,
                                  color: AppTheme.warmGray400,
                                  height: 1.4)),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 延期任务的小卡片
  Widget _buildOverdueTile(Task task) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          // 完成按钮
          FxInkWell(
            onTap: () => widget.onToggleTask(task),
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.warmGray300, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 10),
          // 标题
          Expanded(
            child: Text(
              task.title,
              style: TextStyle(
                fontSize: AppTheme.textMd,
                height: 1.5,
                color: AppTheme.warmGray500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // 顺延按钮
          FxInkWell(
            onTap: () => widget.onPostponeTask(task),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '顺延',
                style: TextStyle(
                  fontSize: AppTheme.textXs,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 删除按钮（带确认）
          FxInkWell(
            onTap: () async {
              final confirmed = await FxDialog.confirm(
                context: context,
                title: '确认删除',
                content: '确定删除「${task.title}」吗？',
                confirmText: '删除',
                destructive: true,
              );
              if (confirmed == true) widget.onDeleteTask(task);
            },
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: AppTheme.warmGray400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
