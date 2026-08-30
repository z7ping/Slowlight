import 'package:flutter/material.dart';

import '../models/tag.dart';
import '../models/task_filter_sort.dart';
import '../models/todo_list.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../utils/color_utils.dart';

/// 任务筛选排序底部弹窗
class TaskFilterSortSheet extends StatefulWidget {
  final TaskFilterSort current;
  final List<TodoList> lists;

  const TaskFilterSortSheet({
    super.key,
    required this.current,
    required this.lists,
  });

  static Future<TaskFilterSort?> show(
    BuildContext context, {
    required TaskFilterSort current,
    required List<TodoList> lists,
  }) {
    return showModalBottomSheet<TaskFilterSort>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => TaskFilterSortSheet(current: current, lists: lists),
    );
  }

  @override
  State<TaskFilterSortSheet> createState() => _TaskFilterSortSheetState();
}

class _TaskFilterSortSheetState extends State<TaskFilterSortSheet> {
  late TaskSortBy _sortBy;
  late SortDirection _sortDirection;
  int? _filterListId;
  int? _filterTagId;
  String? _filterPriority;
  bool? _filterCompleted;
  List<Tag> _tags = [];
  bool _loadingTags = true;

  @override
  void initState() {
    super.initState();
    _sortBy = widget.current.sortBy;
    _sortDirection = widget.current.sortDirection;
    _filterListId = widget.current.filterListId;
    _filterTagId = widget.current.filterTagId;
    _filterPriority = widget.current.filterPriority;
    _filterCompleted = widget.current.filterCompleted;
    _loadTags();
  }

  Future<void> _loadTags() async {
    try {
      final tags = await ApiService.getTags();
      if (mounted) {
        setState(() {
          _tags = tags;
          _loadingTags = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingTags = false);
    }
  }

  void _apply() {
    Navigator.pop(
      context,
      TaskFilterSort(
        sortBy: _sortBy,
        sortDirection: _sortDirection,
        filterListId: _filterListId,
        filterTagId: _filterTagId,
        filterPriority: _filterPriority,
        filterCompleted: _filterCompleted,
      ),
    );
  }

  void _reset() {
    setState(() {
      _sortBy = TaskSortBy.createdAt;
      _sortDirection = SortDirection.desc;
      _filterListId = null;
      _filterTagId = null;
      _filterPriority = null;
      _filterCompleted = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottomPadding),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppTheme.warmGray300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Text(
                '筛选与排序',
                style: SlowlightTypography.cardTitle(
                  context,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              FxButton(
                label: '重置',
                variant: FxButtonVariant.ghost,
                size: FxButtonSize.sm,
                onPressed: _reset,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('排序方式'),
                  const SizedBox(height: 8),
                  _buildSortOptions(),
                  const SizedBox(height: 16),
                  _sectionTitle('排序方向'),
                  const SizedBox(height: 8),
                  _buildSortDirection(),
                  const SizedBox(height: 20),
                  FxSeparator.horizontal(
                    color: AppTheme.warmBorder.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  _sectionTitle('按清单'),
                  const SizedBox(height: 8),
                  _buildListFilter(),
                  const SizedBox(height: 16),
                  _sectionTitle('按标签'),
                  const SizedBox(height: 8),
                  _buildTagFilter(),
                  const SizedBox(height: 16),
                  _sectionTitle('按优先级'),
                  const SizedBox(height: 8),
                  _buildPriorityFilter(),
                  const SizedBox(height: 16),
                  _sectionTitle('按状态'),
                  const SizedBox(height: 8),
                  _buildCompletedFilter(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FxButton(label: '应用', onPressed: _apply),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String label) {
    return Text(
      label,
      style: SlowlightTypography.secondary(
        context,
      ).copyWith(fontWeight: FontWeight.w600, color: AppTheme.warmGray500),
    );
  }

  Widget _buildSortOptions() {
    final options = [
      (TaskSortBy.priority, '优先级', Icons.flag_outlined),
      (TaskSortBy.createdAt, '创建时间', Icons.access_time),
      (TaskSortBy.dueDate, '到期时间', Icons.event_outlined),
      (TaskSortBy.title, '标题', Icons.sort_by_alpha),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          options.map((opt) {
            final selected = _sortBy == opt.$1;
            return _buildChip(
              label: opt.$2,
              icon: opt.$3,
              isSelected: selected,
              onTap: () => setState(() => _sortBy = opt.$1),
            );
          }).toList(),
    );
  }

  Widget _buildSortDirection() {
    return Row(
      children: [
        Expanded(
          child: _buildChip(
            label: '升序',
            icon: Icons.arrow_upward,
            isSelected: _sortDirection == SortDirection.asc,
            onTap: () => setState(() => _sortDirection = SortDirection.asc),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildChip(
            label: '降序',
            icon: Icons.arrow_downward,
            isSelected: _sortDirection == SortDirection.desc,
            onTap: () => setState(() => _sortDirection = SortDirection.desc),
          ),
        ),
      ],
    );
  }

  Widget _buildListFilter() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildChip(
          label: '全部',
          isSelected: _filterListId == null,
          onTap: () => setState(() => _filterListId = null),
        ),
        ...widget.lists.map((list) {
          final selected = _filterListId == list.id;
          return _buildChip(
            label: list.name,
            isSelected: selected,
            color: ColorUtils.safeParse(list.color),
            onTap:
                () => setState(() => _filterListId = selected ? null : list.id),
          );
        }),
      ],
    );
  }

  Widget _buildTagFilter() {
    if (_loadingTags) {
      return const SizedBox(
        height: 32,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: FxCircularProgress(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_tags.isEmpty) {
      return Text(
        '暂无标签',
        style: SlowlightTypography.caption(
          context,
        ).copyWith(color: AppTheme.warmGray400),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildChip(
          label: '全部',
          isSelected: _filterTagId == null,
          onTap: () => setState(() => _filterTagId = null),
        ),
        ..._tags.map((tag) {
          final selected = _filterTagId == tag.id;
          return _buildChip(
            label: tag.name,
            isSelected: selected,
            color: ColorUtils.safeParse(tag.color),
            onTap:
                () => setState(() => _filterTagId = selected ? null : tag.id),
          );
        }),
      ],
    );
  }

  Widget _buildPriorityFilter() {
    final options = [
      (null, '全部', null),
      ('urgent_important', '重要且紧急', AppTheme.priorityUrgentImportant),
      ('important', '重要不紧急', AppTheme.priorityImportant),
      ('urgent', '紧急不重要', AppTheme.priorityUrgent),
      ('none', '不重要不紧急', AppTheme.warmGray400),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          options.map((opt) {
            final selected = _filterPriority == opt.$1;
            return _buildChip(
              label: opt.$2,
              isSelected: selected,
              color: opt.$3,
              onTap:
                  () => setState(
                    () => _filterPriority = selected ? null : opt.$1,
                  ),
            );
          }).toList(),
    );
  }

  Widget _buildCompletedFilter() {
    final options = [
      (null, '全部', Icons.list),
      (false, '未完成', Icons.radio_button_unchecked),
      (true, '已完成', Icons.check_circle_outline),
    ];
    return Row(
      children:
          options.map((opt) {
            final selected = _filterCompleted == opt.$1;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildChip(
                  label: opt.$2,
                  icon: opt.$3,
                  isSelected: selected,
                  onTap:
                      () => setState(
                        () => _filterCompleted = selected ? null : opt.$1,
                      ),
                ),
              ),
            );
          }).toList(),
    );
  }

  Widget _buildChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
    Color? color,
  }) {
    final chipColor = color ?? AppTheme.primary;
    return FxInkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? chipColor.withValues(alpha: 0.1)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                isSelected
                    ? chipColor.withValues(alpha: 0.4)
                    : AppTheme.warmBorder,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isSelected ? chipColor : AppTheme.warmGray500,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: SlowlightTypography.secondary(context).copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? chipColor : AppTheme.warmGray500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
