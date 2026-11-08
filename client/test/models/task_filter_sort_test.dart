import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/task_filter_sort.dart';
import 'package:slowlight/screens/day_view_screen.dart';

Task _task(int id, String title, {
  DateTime? dueDate,
  bool completed = false,
  String priority = 'none',
  DateTime? createdAt,
}) => Task(
  id: id,
  listId: 1,
  title: title,
  priority: priority,
  dueDate: dueDate,
  isCompleted: completed,
  createdAt: createdAt ?? DateTime(2026, 11, 8),
);

void main() {
  test('X03 到期日升降序都把无日期任务排在最后', () {
    final items = [
      _task(1, '未安排'),
      _task(2, '较早', dueDate: DateTime(2026, 11, 5)),
      _task(3, '较晚', dueDate: DateTime(2026, 11, 9)),
    ];
    final asc = items.applyFilterSort(const TaskFilterSort(
      sortBy: TaskSortBy.dueDate,
      sortDirection: SortDirection.asc,
    ));
    final desc = items.applyFilterSort(const TaskFilterSort(
      sortBy: TaskSortBy.dueDate,
      sortDirection: SortDirection.desc,
    ));
    expect(asc.map((task) => task.id).toList(), [2, 3, 1]);
    expect(desc.map((task) => task.id).toList(), [3, 2, 1]);
  });

  test('X03 同优先级或同创建时间排序稳定，不抖动行顺序', () {
    final created = DateTime(2026, 11, 8);
    final items = [
      _task(3, '第三项', createdAt: created),
      _task(1, '第一项', createdAt: created),
      _task(2, '第二项', createdAt: created),
    ];
    for (final direction in SortDirection.values) {
      final sorted = items.applyFilterSort(TaskFilterSort(
        sortBy: TaskSortBy.createdAt,
        sortDirection: direction,
      ));
      expect(sorted.map((task) => task.id).toList(), [3, 1, 2]);
    }
  });

  test('X03 日视图严格使用 Sheet 的排序和已完成状态筛选', () {
    final items = [
      _task(1, '乙：完成', completed: true),
      _task(2, '乙：待办'),
      _task(3, '甲：完成', completed: true),
      _task(4, '甲：待办'),
    ];
    final all = DayViewScreenState.filterTasksForDay(items, const TaskFilterSort(
      sortBy: TaskSortBy.title,
      sortDirection: SortDirection.asc,
    ));
    expect(all.map((task) => task.id).toList(), [4, 2, 3, 1]);

    final completed = DayViewScreenState.filterTasksForDay(
      items,
      const TaskFilterSort(
        sortBy: TaskSortBy.title,
        sortDirection: SortDirection.desc,
        filterCompleted: true,
      ),
    );
    expect(completed.map((task) => task.id).toList(), [1, 3]);

    final pending = DayViewScreenState.filterTasksForDay(
      items,
      const TaskFilterSort(filterCompleted: false),
    );
    expect(pending.map((task) => task.id).toList(), [2, 4]);
  });

  test('X03 日视图四象限优先级与选定排序一致', () {
    final items = [
      _task(1, '普通', priority: 'none'),
      _task(2, '重要不紧急', priority: 'important'),
      _task(3, '重要且紧急', priority: 'urgent_important'),
      _task(4, '紧急不重要', priority: 'urgent'),
    ];
    final sorted = DayViewScreenState.filterTasksForDay(items,
      const TaskFilterSort(
        sortBy: TaskSortBy.priority,
        sortDirection: SortDirection.desc,
      ),
    );
    expect(sorted.map((task) => task.id).toList(), [3, 2, 4, 1]);
  });
}
