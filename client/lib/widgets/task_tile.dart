import '../ui/fx.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../models/task.dart';
import '../theme/app_theme.dart';
import '../utils/color_utils.dart';

class TaskTile extends StatelessWidget {
  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback? onPostpone;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool compact;
  final bool isSelected;

  const TaskTile({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onDelete,
    this.onPostpone,
    this.onTap,
    this.onLongPress,
    this.compact = false,
    this.isSelected = false,
  });

  String _formatDueDate() {
    if (task.dueDate == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(task.dueDate!.year, task.dueDate!.month, task.dueDate!.day);
    final diff = due.difference(today).inDays;

    String dateStr;
    if (diff == 0) {
      dateStr = '今天';
    } else if (diff == 1) {
      dateStr = '明天';
    } else if (diff == -1) {
      dateStr = '昨天';
    } else if (diff > 0 && diff <= 7) {
      const weekdays = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      dateStr = weekdays[task.dueDate!.weekday];
    } else {
      dateStr = '${task.dueDate!.month}/${task.dueDate!.day}';
    }

    if (task.dueTime != null) {
      dateStr += ' ${task.dueTime}';
    }
    return dateStr;
  }

  @override
  Widget build(BuildContext context) {
    final isOverdue = task.dueDate != null &&
        !task.isCompleted &&
        task.dueDate!.isBefore(DateTime.now());

    // 紧凑模式：无卡片，单行布局，支持滑动手势
    if (compact) {
      final compactTile = Semantics(
        label: task.title + (task.isCompleted ? ' (已完成)' : ''),
        child: FxInkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  // 勾选框
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                          value: task.isCompleted,
                          onChanged: (_) => onToggle(),
                          activeColor: AppTheme.primary,
                          side: BorderSide(color: AppTheme.warmGray400, width: 1.5),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 标题
                  Expanded(
                    child: Text(
                      task.title,
                      style: TextStyle(
                        fontSize: AppTheme.textMd, height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: task.isCompleted
                            ? AppTheme.warmGray400
                            : Theme.of(context).colorScheme.onSurface,
                        decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                        decorationColor: AppTheme.warmGray400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 标签（紧凑显示）
                  if (task.tags.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    ...task.tags.take(2).map((tag) => Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: ColorUtils.safeParse(tag.color ?? '#999'),
                          shape: BoxShape.circle,
                        ),
                      ),
                    )),
                  ],
                  // 系统标签图标
                  if (task.systemTagId != null) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.label_outline, size: 14, color: AppTheme.warmGray400),
                  ],
                ],
              ),
            ),
          ),
        ),
      );

      // 包裹 Dismissible 实现滑动手势
      return Dismissible(
        key: Key('compact-task-${task.id}'),
        direction: DismissDirection.horizontal,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            // 右滑 → 打卡完成
            onToggle();
            return false; // 不移除，由 onToggle 刷新
          }
          // 左滑 → 删除（带确认对话框）
          return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('确认删除'),
              content: Text('确定删除「${task.title}」吗？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.priorityHigh,
                  ),
                  child: const Text('删除'),
                ),
              ],
            ),
          );
        },
        // 右滑背景（打卡完成）
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.check_circle_outline,
            color: AppTheme.success,
          ),
        ),
        // 左滑背景（删除）
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: AppTheme.priorityHigh.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.delete_outline,
            color: AppTheme.priorityHigh,
          ),
        ),
        onDismissed: (direction) => onDelete(),
        child: compactTile,
      );
    }

    // 标准模式（保留原有卡片样式）
    return Semantics(
      label: task.title + (task.isCompleted ? ' (已完成)' : ''),
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: isSelected
            ? AppTheme.primaryLight
            : task.isCompleted
                ? Theme.of(context).colorScheme.surfaceContainerLow
                : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: FxInkWell(
          onTap: onTap,
          onLongPress: onLongPress ?? () => _showQuickActions(context),
          borderRadius: BorderRadius.circular(12),
          child: Dismissible(
            key: Key('task-${task.id}'),
            // 左滑 → 完成
            direction: DismissDirection.horizontal,
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.startToEnd) {
                // 左滑完成
                onToggle();
                return false; // 不移除，由 onToggle 刷新
              }
              // 右滑删除
              return await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('确认删除'),
                  content: Text('确定删除「${task.title}」吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.priorityHigh,
                      ),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              );
            },
            // 左滑背景（完成）
            background: Container(
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.only(left: 20),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.check_circle_outline,
                color: AppTheme.success,
              ),
            ),
            // 右滑背景（删除）
            secondaryBackground: Container(
              alignment: Alignment.centerRight,
              padding: EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: AppTheme.priorityHigh.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.delete_outline,
                color: AppTheme.priorityHigh,
              ),
            ),
            onDismissed: (direction) => onDelete(),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: isOverdue ? AppTheme.priorityHigh.withValues(alpha: 0.04) : null,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: task.priority == 'urgent_important'
                      ? AppTheme.priorityUrgentImportant.withValues(alpha: 0.4)
                      : task.priority == 'important' || task.priority == 'urgent'
                          ? AppTheme.priorityColor(task.priority).withValues(alpha: 0.3)
                          : AppTheme.warmBorder,
                  width: task.priority == 'urgent_important' ? 1.5 : 1,
                ),
              ),
              foregroundDecoration: task.priority != 'none' && !task.isCompleted
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border(
                        left: BorderSide(
                          color: AppTheme.priorityColor(task.priority),
                          width: 4,
                        ),
                      ),
                    )
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左侧：优先级竖条 + Checkbox
                  _buildLeading(isOverdue: isOverdue),
                  const SizedBox(width: 12),

                  // 中间：标题 + 副信息
                  Expanded(child: _buildContent(isOverdue, context)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildLeading({bool isOverdue = false}) {
    return Column(
      children: [
        SizedBox(height: 2),
        // 优先级竖条
        Container(
          width: 6,
          height: 28,
          decoration: BoxDecoration(
            color: isOverdue ? AppTheme.priorityHigh : AppTheme.priorityColor(task.priority),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        SizedBox(height: 8),
        // Checkbox
        SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: task.isCompleted,
                onChanged: (_) => onToggle(),
                activeColor: AppTheme.primary,
                side: BorderSide(
                  color: AppTheme.warmGray400,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(bool isOverdue, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 任务标题
        Text(
          task.title,
          style: TextStyle(
            fontSize: AppTheme.textMd, height: 1.5,
            fontWeight: FontWeight.w500,
            color: task.isCompleted
                ? AppTheme.warmGray500
                : Theme.of(context).colorScheme.onSurface,
            decoration: task.isCompleted
                ? TextDecoration.lineThrough
                : null,
            decorationColor: AppTheme.warmGray500,
          ),
        ),

        // 副信息行
        if (_hasSubtitle()) ...[
          const SizedBox(height: 6),
          _buildSubtitle(isOverdue),
        ],

        // 标签
        if (!compact && task.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildTags(),
        ],

        // 子任务进度条
        if (!compact && task.subtaskCount > 0) ...[
          SizedBox(height: 8),
          _buildSubtaskProgress(),
        ],
      ],
    );
  }

  bool _hasSubtitle() {
    return task.list != null ||
        task.dueDate != null ||
        task.isRepeat ||
        task.reminderAt != null;
  }

  Widget _buildSubtitle(bool isOverdue) {
    final chips = <Widget>[];

    // 清单名称
    if (task.list != null) {
      chips.add(_buildChip(
        icon: Icons.folder_outlined,
        text: task.list!.name,
        color: AppTheme.warmGray500,
      ));
    }

    // 截止日期
    final dueText = _formatDueDate();
    if (dueText.isNotEmpty) {
      chips.add(_buildChip(
        icon: Icons.schedule,
        text: dueText,
        color: isOverdue ? AppTheme.priorityHigh : AppTheme.warmGray500,
      ));
    }

    // 重复标记
    if (task.isRepeat) {
      chips.add(_buildChip(
        icon: Icons.repeat,
        text: task.repeatText,
        color: AppTheme.primary,
      ));
    }

    // 提醒标记
    if (task.reminderAt != null) {
      chips.add(_buildChip(
        icon: Icons.notifications_outlined,
        text: '已提醒',
        color: AppTheme.warning,
      ));
    }

    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: chips,
    );
  }

  Widget _buildChip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          if (text.isNotEmpty) ...[
            const SizedBox(width: 3),
            Text(
              text,
              style: TextStyle(
                fontSize: AppTheme.textMd, height: 1.5,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTags() {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: task.tags.map((tag) {
        final color = ColorUtils.safeParse(tag.color, fallback: AppTheme.warmGray300);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
          ),
          child: Text(
            tag.name,
            style: TextStyle(
              fontSize: AppTheme.textXs, height: 1.4,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSubtaskProgress() {
    final progress = task.subtaskCount > 0
        ? task.completedSubtask / task.subtaskCount
        : 0.0;
    final isAllDone = task.completedSubtask == task.subtaskCount;

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: AppTheme.warmBorder,
              valueColor: AlwaysStoppedAnimation<Color>(
                isAllDone ? AppTheme.success : AppTheme.primary,
              ),
            ),
          ),
        ),
        SizedBox(width: 8),
        Text(
          '${task.completedSubtask}/${task.subtaskCount}',
          style: TextStyle(
            fontSize: AppTheme.textXs, height: 1.4,
            fontWeight: FontWeight.w500,
            color: isAllDone ? AppTheme.success : AppTheme.warmGray500,
          ),
        ),
      ],
    );
  }

  /// 快捷操作底部菜单
  void _showQuickActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.warmGray400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(Icons.check_circle_outline, color: AppTheme.success),
                title: const Text('完成'),
                onTap: () {
                  Navigator.pop(ctx);
                  onToggle();
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppTheme.priorityHigh),
                title: const Text('删除'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirm = await showDialog<bool>(
                    context: ctx,
                    builder: (dCtx) => AlertDialog(
                      title: const Text('确认删除'),
                      content: Text('确定删除「${task.title}」吗？'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('取消')),
                        TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('删除')),
                      ],
                    ),
                  );
                  if (confirm == true) onDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
