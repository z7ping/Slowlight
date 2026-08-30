import 'package:flutter/material.dart';

import '../models/task.dart';
import '../models/todo_list.dart';
import '../services/data_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../utils/color_utils.dart';
import '../widgets/task_detail_sheet.dart';

/// 收集箱页面
///
/// 快速捕获想法，稍后整理到清单。
/// 功能：查看收集箱任务、快速添加、移动到清单、点击查看详情。
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<Task> _tasks = [];
  List<TodoList> _allLists = [];
  bool _isLoading = true;
  final _quickAddController = TextEditingController();
  final _quickAddFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _quickAddController.dispose();
    _quickAddFocus.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      final data = await ApiService.getInbox();
      final lists = await ApiService.getLists();
      if (!mounted) return;
      setState(() {
        _tasks = (data['tasks'] as List).map((t) => Task.fromJson(t)).toList();
        _allLists = lists;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _quickAdd() async {
    final title = _quickAddController.text.trim();
    if (title.isEmpty) return;
    _quickAddController.clear();
    _quickAddFocus.requestFocus();

    try {
      final task = await DataService().quickAddToInbox(title);
      if (!mounted) return;
      setState(() => _tasks.insert(0, task));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e')),
        );
      }
    }
  }

  Future<void> _moveTo(Task task) async {
    if (_allLists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有其他清单，先去创建一个吧')),
      );
      return;
    }

    final selected = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _MoveToListSheet(lists: _allLists),
    );

    if (selected == null) return;

    try {
      await ApiService.moveInboxTask(task.id, selected);
      if (!mounted) return;
      setState(() => _tasks.removeWhere((t) => t.id == task.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已移动到「${_allLists.firstWhere((l) => l.id == selected).name}」',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('移动失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.warmWhite,
      body: SafeArea(
        child: Column(
          children: [
            FxPageHeader(
              title: '收集箱',
              onBack: () => Navigator.of(context).pop(),
            ),
            _buildQuickAddBar(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _tasks.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadAll,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            itemCount: _tasks.length,
                            itemBuilder: (context, index) {
                              final task = _tasks[index];
                              return Dismissible(
                                key: ValueKey(task.id),
                                background: _buildSwipeBackground(
                                  color: AppTheme.success,
                                  icon: Icons.drive_file_move_outline,
                                  alignment: Alignment.centerLeft,
                                ),
                                secondaryBackground: _buildSwipeBackground(
                                  color: AppTheme.priorityHigh,
                                  icon: Icons.delete_outline,
                                  alignment: Alignment.centerRight,
                                ),
                                confirmDismiss: (direction) async {
                                  if (direction == DismissDirection.startToEnd) {
                                    _moveTo(task);
                                    return false;
                                  }

                                  final confirmed = await FxDialog.confirm(
                                    context: context,
                                    title: '删除任务',
                                    content: '确定删除「${task.title}」？',
                                    confirmText: '删除',
                                    destructive: true,
                                  );
                                  if (confirmed != true) return false;

                                  final originalTasks = List<Task>.from(_tasks);
                                  var undone = false;
                                  setState(
                                    () => _tasks.removeWhere(
                                      (t) => t.id == task.id,
                                    ),
                                  );
                                  ScaffoldMessenger.of(context).clearSnackBars();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('已删除「${task.title}」'),
                                      action: SnackBarAction(
                                        label: '撤销',
                                        onPressed: () {
                                          undone = true;
                                          setState(() => _tasks = originalTasks);
                                        },
                                      ),
                                      duration: const Duration(seconds: 4),
                                    ),
                                  );
                                  await Future.delayed(
                                    const Duration(seconds: 4),
                                  );
                                  if (undone) return false;
                                  try {
                                    await ApiService.deleteTask(task.id);
                                  } catch (_) {
                                    if (mounted) {
                                      setState(() => _tasks = originalTasks);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: const Text('删除失败'),
                                          backgroundColor: AppTheme.priorityHigh,
                                        ),
                                      );
                                    }
                                  }
                                  return false;
                                },
                                child: FxCard(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  borderRadius: 12,
                                  padding: EdgeInsets.zero,
                                  child: FxListTile(
                                    title: task.title,
                                    subtitle: _timeAgo(task.createdAt),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    titleStyle: SlowlightTypography.body(context),
                                    subtitleStyle:
                                        SlowlightTypography.caption(context)
                                            .copyWith(color: AppTheme.warmGray400),
                                    trailing: FxIconButton(
                                      icon: Icons.drive_file_move_outline,
                                      iconSize: 20,
                                      tooltip: '移动到清单',
                                      onPressed: () => _moveTo(task),
                                    ),
                                    onTap: () {
                                      TaskDetailSheet.show(
                                        context,
                                        task: task,
                                        lists: _allLists,
                                        onChanged: _loadAll,
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAddBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            child: FxInput(
              controller: _quickAddController,
              focusNode: _quickAddFocus,
              placeholder: '快速记录想法...',
              placeholderStyle: SlowlightTypography.secondary(context)
                  .copyWith(color: AppTheme.warmGray400),
              style: SlowlightTypography.body(context),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _quickAdd(),
              isDense: true,
            ),
          ),
          const SizedBox(width: 10),
          FxButton(
            label: '添加',
            size: FxButtonSize.sm,
            onPressed: _quickAdd,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return FxEmptyState(
      emoji: '📥',
      title: '收集箱是空的',
      subtitle: '快速记录想法，稍后整理到清单',
    );
  }

  Widget _buildSwipeBackground({
    required Color color,
    required IconData icon,
    required Alignment alignment,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Icon(icon, color: AppTheme.white),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}

class _MoveToListSheet extends StatelessWidget {
  final List<TodoList> lists;

  const _MoveToListSheet({required this.lists});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '移动到清单',
                style: SlowlightTypography.cardTitle(context),
              ),
            ),
            Divider(height: 1, color: fxDivider(context)),
            ...lists.map(
              (list) => FxListTile(
                title: list.name,
                leading: Icon(
                  Icons.folder_outlined,
                  color: ColorUtils.safeParse(list.color),
                ),
                onTap: () => Navigator.pop(context, list.id),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
