import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/task_tile.dart';
import '../widgets/task_detail_sheet.dart';
import '../models/todo_list.dart';
import '../models/task_filter_sort.dart';
import '../widgets/task_filter_sort_sheet.dart';
import 'package:slowlight/ui/fx.dart';

/// 天视图 — 7天日期条 + PageView滑动
class DayViewScreen extends StatefulWidget {
  final List<TodoList> lists;
  final VoidCallback? onChanged;

  const DayViewScreen({super.key, required this.lists, this.onChanged});

  @override
  State<DayViewScreen> createState() => DayViewScreenState();
}

class DayViewScreenState extends State<DayViewScreen> {
  late PageController _pageController;
  DateTime _selectedDate = DateTime.now();
  List<Task> _allMonthTasks = [];
  bool _isLoading = true;
  TaskFilterSort _filterSort = const TaskFilterSort();

  Map<String, List<Task>> get _tasksByDate {
    final map = <String, List<Task>>{};
    for (final task in _allMonthTasks) {
      if (task.dueDate != null) {
        final key = DateFormat('yyyy-MM-dd').format(task.dueDate!.toLocal());
        map.putIfAbsent(key, () => []).add(task);
      }
    }
    return map;
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1000);
    _loadMonthTasks(_selectedDate);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadMonthTasks(DateTime date) async {
    setState(() => _isLoading = true);
    try {
      final tasks = await ApiService.getTasksForMonth(date.year, date.month);
      if (!mounted) return;
      setState(() {
        _allMonthTasks = tasks;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  /// The day view keeps pending tasks ahead of completed facts, while
  /// honoring every filter and sort choice of the shared task sheet.
  /// Partitioning an already-sorted result retains ordering within each group.
  static List<Task> filterTasksForDay(List<Task> tasks, TaskFilterSort filters) {
    final sorted = tasks.applyFilterSort(filters);
    return [
      ...sorted.where((task) => !task.isCompleted),
      ...sorted.where((task) => task.isCompleted),
    ];
  }

  List<Task> _tasksForDay(DateTime day) {
    final key = DateFormat('yyyy-MM-dd').format(day);
    return filterTasksForDay(_tasksByDate[key] ?? const <Task>[], _filterSort);
  }

  DateTime _dateForPage(int page) {
    final base = DateTime.now();
    final offset = page - 1000;
    return DateTime(base.year, base.month, base.day + offset);
  }

  void jumpToToday() {
    _pageController.jumpToPage(1000);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildWeekStrip(),
        Expanded(
          child:
              _isLoading
                  ? const Center(child: FxCircularProgress())
                  : PageView.builder(
                    controller: _pageController,
                    onPageChanged: (page) {
                      final date = _dateForPage(page);
                      final previous = _selectedDate;
                      setState(() => _selectedDate = date);
                      if (date.month != previous.month ||
                          date.year != previous.year) {
                        _loadMonthTasks(date);
                      }
                    },
                    itemBuilder: (context, index) {
                      final date = _dateForPage(index);
                      final tasks = _tasksForDay(date);
                      return _buildDayPage(date, tasks);
                    },
                  ),
        ),
      ],
    );
  }

  /// 7天日期条
  Widget _buildWeekStrip() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 显示7天：选中日前3天 + 选中日 + 后3天
    final centerDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final days = List.generate(7, (i) => centerDay.add(Duration(days: i - 3)));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          ...days.map((day) {
            final isToday = day.isAtSameMomentAs(today);
            final isSelected = day.isAtSameMomentAs(centerDay);
            final hasTasks = _tasksForDay(day).isNotEmpty;
            final weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() => _selectedDate = day);
                  // 跳转到对应页面
                  final diff = day.difference(today).inDays;
                  _pageController.jumpToPage(1000 + diff);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? AppTheme.primary
                            : isToday
                            ? AppTheme.primaryLight
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '周${weekdayNames[day.weekday - 1]}',
                        style: TextStyle(
                          fontSize: SlowlightTypography.captionSize,
                          color:
                              isSelected
                                  ? AppTheme.white.withValues(alpha: 0.8)
                                  : AppTheme.warmGray400,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: SlowlightTypography.bodySize,
                          fontWeight:
                              isSelected || isToday
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                          color:
                              isSelected
                                  ? AppTheme.white
                                  : isToday
                                  ? AppTheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // 有任务的小圆点
                      SizedBox(
                        height: 4,
                        child:
                            hasTasks
                                ? Container(
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color:
                                        isSelected
                                            ? AppTheme.white
                                            : AppTheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                )
                                : null,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
          // 筛选排序按钮
          FxInkWell(
            onTap: () async {
              final result = await TaskFilterSortSheet.show(
                context,
                current: _filterSort,
                lists: widget.lists,
              );
              if (result != null) {
                setState(() => _filterSort = result);
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Icon(
                  Icons.tune,
                  size: 16,
                  color:
                      _filterSort.hasAnyActive
                          ? Theme.of(context).primaryColor
                          : AppTheme.warmGray400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayPage(DateTime date, List<Task> tasks) {
    if (tasks.isEmpty) {
      return Center(
        child: Text(
          '这天没有安排 🌤️',
          style: TextStyle(
            color: AppTheme.warmGray300,
            fontSize: SlowlightTypography.buttonSize,
          ),
        ),
      );
    }

    return FxRefresh(
      onRefresh: () async => _loadMonthTasks(date),
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final task = tasks[index];
          return TaskTile(
            key: ValueKey(task.id),
            task: task,
            compact: true,
            isSelected: false,
            onToggle: () => _toggleTask(task),
            onDelete: () => _deleteTask(task),
            onTap: () => _openTaskDetail(task),
          );
        },
      ),
    );
  }

  Future<void> _toggleTask(Task task) async {
    try {
      await ApiService.completeTask(task.id);
      _loadMonthTasks(_selectedDate);
      widget.onChanged?.call();
    } catch (e) {}
  }

  Future<void> _deleteTask(Task task) async {
    try {
      await ApiService.deleteTask(task.id);
      _loadMonthTasks(_selectedDate);
      widget.onChanged?.call();
    } catch (e) {}
  }

  void _openTaskDetail(Task task) {
    TaskDetailSheet.show(
      context,
      task: task,
      lists: widget.lists,
      onChanged: () {
        _loadMonthTasks(_selectedDate);
        widget.onChanged?.call();
      },
    );
  }
}
