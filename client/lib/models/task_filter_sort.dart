import 'task.dart';

/// 排序方式
enum TaskSortBy {
  priority, // 按优先级
  createdAt, // 按创建时间
  dueDate, // 按到期时间
  title, // 按标题字母
}

/// 排序方向
enum SortDirection {
  asc, // 升序
  desc, // 降序
}

/// 任务筛选排序状态
class TaskFilterSort {
  final TaskSortBy sortBy;
  final SortDirection sortDirection;

  // 筛选条件（null 表示不过滤）
  final int? filterListId;       // 按清单筛选
  final int? filterTagId;        // 按标签筛选
  final String? filterPriority;  // 按优先级筛选 (none/urgent_important/important/urgent)
  final bool? filterCompleted;   // 按完成状态筛选 (null=全部, true=已完成, false=未完成)

  const TaskFilterSort({
    this.sortBy = TaskSortBy.createdAt,
    this.sortDirection = SortDirection.desc,
    this.filterListId,
    this.filterTagId,
    this.filterPriority,
    this.filterCompleted,
  });

  /// 是否有任何筛选条件处于激活状态
  bool get hasActiveFilter =>
      filterListId != null ||
      filterTagId != null ||
      filterPriority != null ||
      filterCompleted != null;

  /// 是否有排序（非默认）
  bool get hasActiveSort =>
      sortBy != TaskSortBy.createdAt || sortDirection != SortDirection.desc;

  bool get hasAnyActive => hasActiveFilter || hasActiveSort;

  /// 激活的筛选条件数量
  int get activeFilterCount {
    int count = 0;
    if (filterListId != null) count++;
    if (filterTagId != null) count++;
    if (filterPriority != null) count++;
    if (filterCompleted != null) count++;
    return count;
  }

  TaskFilterSort copyWith({
    TaskSortBy? sortBy,
    SortDirection? sortDirection,
    int? Function()? filterListIdFn,
    int? Function()? filterTagIdFn,
    String? Function()? filterPriorityFn,
    bool? Function()? filterCompletedFn,
  }) {
    return TaskFilterSort(
      sortBy: sortBy ?? this.sortBy,
      sortDirection: sortDirection ?? this.sortDirection,
      filterListId: filterListIdFn != null ? filterListIdFn() : filterListId,
      filterTagId: filterTagIdFn != null ? filterTagIdFn() : filterTagId,
      filterPriority: filterPriorityFn != null ? filterPriorityFn() : filterPriority,
      filterCompleted: filterCompletedFn != null ? filterCompletedFn() : filterCompleted,
    );
  }

  /// 重置所有筛选
  TaskFilterSort resetFilters() {
    return TaskFilterSort(
      sortBy: sortBy,
      sortDirection: sortDirection,
    );
  }

  /// 获取优先级的数值权重（用于排序）
  static int priorityWeight(String priority) {
    switch (priority) {
      case 'urgent_important': return 4;
      case 'important': return 3;
      case 'urgent': return 2;
      case 'none': return 1;
      default: return 0;
    }
  }
}

/// 对任务列表应用筛选和排序
extension TaskFilterSortX on List<Task> {
  List<Task> applyFilterSort(TaskFilterSort fs) {
    // 筛选
    var filtered = where((task) {
      if (fs.filterListId != null && task.listId != fs.filterListId) return false;
      if (fs.filterTagId != null &&
          !task.tags.any((t) => t.id == fs.filterTagId)) return false;
      if (fs.filterPriority != null && task.priority != fs.filterPriority) return false;
      if (fs.filterCompleted != null && task.isCompleted != fs.filterCompleted) return false;
      return true;
    }).toList();

    // 排序
    filtered.sort((a, b) {
      int cmp;
      switch (fs.sortBy) {
        case TaskSortBy.priority:
          cmp = TaskFilterSort.priorityWeight(a.priority)
              .compareTo(TaskFilterSort.priorityWeight(b.priority));
          break;
        case TaskSortBy.createdAt:
          cmp = a.createdAt.compareTo(b.createdAt);
          break;
        case TaskSortBy.dueDate:
          final aDate = a.dueDate ?? DateTime(9999);
          final bDate = b.dueDate ?? DateTime(9999);
          cmp = aDate.compareTo(bDate);
          break;
        case TaskSortBy.title:
          cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
      }
      return fs.sortDirection == SortDirection.asc ? cmp : -cmp;
    });

    return filtered;
  }
}
