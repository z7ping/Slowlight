import 'package:flutter/material.dart';
import '../../models/task.dart';
import '../../theme/app_theme.dart';
import '../../ui/fx.dart';

/// 今日待办摘要组件
class TodayTaskSummary extends StatelessWidget {
  final List<Task> tasks;
  final int maxDisplay;
  final ValueChanged<Task>? onTaskTap;
  final ValueChanged<Task>? onTaskToggle;
  final VoidCallback? onViewAll;
  final VoidCallback? onQuickAdd;

  const TodayTaskSummary({
    super.key,
    required this.tasks,
    this.maxDisplay = 3,
    this.onTaskTap,
    this.onTaskToggle,
    this.onViewAll,
    this.onQuickAdd,
  });

  @override
  Widget build(BuildContext context) {
    final completedCount = tasks.where((t) => t.isCompleted).length;
    final pendingTasks = tasks.where((t) => !t.isCompleted).toList();
    final displayTasks = pendingTasks.take(maxDisplay).toList();

    return FxCard(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Icon(
                Icons.checklist_outlined,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '今日待办',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$completedCount/${tasks.length}',
                  style: TextStyle(
                    fontSize: AppTheme.textSm,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const Spacer(),
              if (onViewAll != null)
                FxGestureDetector(
                  onTap: onViewAll,
                  child: Row(
                    children: [
                      Text(
                        '全部',
                        style: TextStyle(
                          fontSize: AppTheme.textSm,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // 任务列表
          if (displayTasks.isEmpty)
            _buildEmptyState(context)
          else
            ...displayTasks.map((task) => _buildTaskItem(context, task)),
          // 快速添加
          if (onQuickAdd != null) ...[
            const SizedBox(height: 8),
            FxGestureDetector(
              onTap: onQuickAdd,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.add,
                      size: 16,
                      color: AppTheme.warmGray500,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '快速添加...',
                      style: TextStyle(
                        fontSize: AppTheme.textSm,
                        color: AppTheme.warmGray500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTaskItem(BuildContext context, Task task) {
    return FxGestureDetector(
      onTap: () => onTaskTap?.call(task),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            // 完成按钮
            FxGestureDetector(
              onTap: () => onTaskToggle?.call(task),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _getPriorityColor(task.priority),
                    width: 2,
                  ),
                ),
                child: task.isCompleted
                    ? Icon(
                        Icons.check,
                        size: 14,
                        color: _getPriorityColor(task.priority),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            // 任务标题
            Expanded(
              child: Text(
                task.title,
                style: TextStyle(
                  fontSize: AppTheme.textMd,
                  decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                  color: task.isCompleted
                      ? AppTheme.warmGray500
                      : Theme.of(context).colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 优先级标签
            if (task.priority != 'none' && !task.isCompleted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getPriorityColor(task.priority).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _getPriorityLabel(task.priority),
                  style: TextStyle(
                    fontSize: AppTheme.textXs,
                    color: _getPriorityColor(task.priority),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Column(
          children: [
            const Text('✨', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 8),
            Text(
              '今天没有待办任务',
              style: TextStyle(
                fontSize: AppTheme.textSm,
                color: AppTheme.warmGray500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'urgent_important':
        return AppTheme.priorityUrgentImportant;
      case 'important':
        return AppTheme.priorityImportant;
      case 'urgent':
        return AppTheme.priorityUrgent;
      default:
        return AppTheme.warmGray400;
    }
  }

  String _getPriorityLabel(String priority) {
    switch (priority) {
      case 'urgent_important':
        return '紧急';
      case 'important':
        return '重要';
      case 'urgent':
        return '紧急';
      default:
        return '';
    }
  }
}
