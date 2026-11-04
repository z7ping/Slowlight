import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
  // Test seams for creation-result recovery without a live service.
  final Future<({List<Task> tasks, List<TodoList> lists})> Function()? dataLoader;
  final Future<Task> Function(String title)? createTask;

  const InboxScreen({super.key, this.dataLoader, this.createTask});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<Task> _tasks = [];
  List<TodoList> _allLists = [];
  bool _isLoading = true;
  final _quickAddController = TextEditingController();
  final _quickAddFocus = FocusNode();
  bool _quickAdding = false;

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
      final values = widget.dataLoader != null
          ? await widget.dataLoader!()
          : await (() async {
              final data = await ApiService.getInbox();
              final lists = await ApiService.getLists();
              final tasks = (data['tasks'] as List)
                  .map((t) => t is Task
                      ? t
                      : Task.fromJson(Map<String, dynamic>.from(t as Map)))
                  .toList();
              return (tasks: tasks, lists: lists);
            })();
      if (!mounted) return;
      setState(() {
        _tasks = values.tasks;
        _allLists = values.lists;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _quickAdd() async {
    if (_quickAdding) return;
    final title = _quickAddController.text.trim();
    if (title.isEmpty) return;
    setState(() => _quickAdding = true);
    try {
      final task = await (widget.createTask?.call(title) ??
          DataService().quickAddToInbox(title));
      if (!mounted) return;
      // Clear only the submitted value, not anything typed while saving.
      if (_quickAddController.text.trim() == title) {
        _quickAddController.clear();
      }
      setState(() => _tasks.insert(0, task));
      _quickAddFocus.requestFocus();
    } catch (_) {
      if (mounted) {
        FxNotice.showContent(
          context,
          const Text('创建结果未确认，已保留输入；请核对收集箱后再重试'),
        );
      }
    } finally {
      if (mounted) setState(() => _quickAdding = false);
    }
  }

  Future<void> _moveTo(Task task) async {
    if (_allLists.isEmpty) {
      FxNotice.showContent(context, Text('还没有其他清单，先去创建一个吧'));
      return;
    }

    final selected = await FxSheet.show<int>(
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
      FxNotice.showContent(
        context,
        Text('已移动到「${_allLists.firstWhere((l) => l.id == selected).name}」'),
      );
    } catch (e) {
      if (mounted) {
        FxNotice.showContent(context, Text('移动失败: $e'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            FxPageHeader(
              title: '收集箱',
              onBack: () => Navigator.of(context).pop(),
            ),
            _buildQuickAddBar(),
            Expanded(
              child:
                  _isLoading
                      ? const Center(child: FxCircularProgress())
                      : _tasks.isEmpty
                      ? _buildEmptyState()
                      : FxRefresh(
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
                                icon: LucideIcons.folderInput,
                                alignment: Alignment.centerLeft,
                              ),
                              secondaryBackground: _buildSwipeBackground(
                                color: AppTheme.priorityHigh,
                                icon: LucideIcons.trash2,
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
                                FxNotice.clear(context);
                                FxNotice.showContent(
                                  context,
                                  Text('已删除「${task.title}」'),
                                  action: FxNoticeAction(
                                    label: '撤销',
                                    onPressed: () {
                                      undone = true;
                                      setState(() => _tasks = originalTasks);
                                    },
                                  ),
                                  duration: const Duration(seconds: 4),
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
                                    FxNotice.showContent(
                                      context,
                                      const Text('删除失败'),
                                      variant: FxNoticeVariant.destructive,
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
                                  subtitleStyle: SlowlightTypography.caption(
                                    context,
                                  ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  trailing: FxIconButton(
                                    icon: LucideIcons.folderInput,
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
              placeholderStyle: SlowlightTypography.secondary(
                context,
              ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              style: SlowlightTypography.body(context),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _quickAdd(),
            ),
          ),
          const SizedBox(width: 10),
          FxButton(
            label: _quickAdding ? '添加中…' : '添加',
            size: FxButtonSize.sm,
            onPressed: _quickAdding ? null : _quickAdd,
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
            FxSeparator.horizontal(height: 1, color: fxDivider(context)),
            ...lists.map(
              (list) => FxListTile(
                title: list.name,
                leading: Icon(
                  LucideIcons.folder,
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
