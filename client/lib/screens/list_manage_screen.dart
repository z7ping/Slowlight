import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/task.dart';
import '../models/todo_list.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../utils/color_utils.dart';

/// 清单管理：作为「更多工具」中的一级内容页嵌入主壳，不再叠加第二层 AppBar。
class ListManageScreen extends StatefulWidget {
  const ListManageScreen({super.key});

  @override
  State<ListManageScreen> createState() => _ListManageScreenState();
}

class _ListManageScreenState extends State<ListManageScreen> {
  bool _loading = true;
  List<TodoList> _lists = const [];
  List<Task> _tasks = const [];

  static const _presetIcons = [
    '📁', '💼', '🏠', '🎯', '💡', '📚', '🎨', '🔧', '❤️', '🌟', '🌱', '📊',
  ];
  static const _presetColors = [
    '#1890FF', '#52C41A', '#FAAD14', '#FF6B6B', '#722ED1', '#13C2C2', '#EB2F96', '#FA8C16',
  ];

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  Future<void> _loadLists() async {
    try {
      final values = await Future.wait<dynamic>([
        DataService().getLists(),
        DataService().getAllTasks(),
      ]);
      if (!mounted) return;
      setState(() {
        _lists = values[0] as List<TodoList>;
        _tasks = values[1] as List<Task>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _taskCountFor(TodoList list) =>
      _tasks.where((task) => task.listId == list.id).length;

  Future<void> _showEditor([TodoList? existing]) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    var selectedIcon = existing?.icon ?? _presetIcons.first;
    var selectedColor = existing?.color ?? _presetColors.first;
    var saving = false;
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .45),
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final theme = Theme.of(dialogContext);
          return Dialog(
            backgroundColor: theme.colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            existing == null ? '新建清单' : '编辑清单',
                            style: SlowlightTypography.cardTitle(dialogContext),
                          ),
                        ),
                        FxIconButton(
                          tooltip: '关闭',
                          onPressed: saving
                              ? null
                              : () => Navigator.pop(dialogContext, false),
                          icon: LucideIcons.x,
                          iconSize: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FxInput(
                      controller: nameController,
                      autofocus: true,
                      enabled: !saving,
                      placeholder: '清单名称',
                      style: SlowlightTypography.body(dialogContext),
                    ),
                    const SizedBox(height: 14),
                    _fieldLabel(dialogContext, '图标'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _presetIcons.map((icon) {
                        final selected = icon == selectedIcon;
                        return FxInkWell(
                          onTap: saving
                              ? null
                              : () => setDialogState(() => selectedIcon = icon),
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? activePalette.accent.withValues(alpha: .12)
                                  : Colors.transparent,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMd),
                              border: Border.all(
                                color: selected
                                    ? activePalette.accent
                                    : theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: Text(
                              icon,
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        );
                      }).toList(growable: false),
                    ),
                    const SizedBox(height: 14),
                    _fieldLabel(dialogContext, '颜色'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _presetColors.map((value) {
                        final selected = value == selectedColor;
                        final color = ColorUtils.safeParse(value);
                        return FxInkWell(
                          onTap: saving
                              ? null
                              : () =>
                                  setDialogState(() => selectedColor = value),
                          borderRadius: BorderRadius.circular(22),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selected
                                        ? theme.colorScheme.onSurface
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(growable: false),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style:
                            SlowlightTypography.caption(dialogContext).copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FxButton(
                          label: '取消',
                          variant: FxButtonVariant.outline,
                          onPressed: saving
                              ? null
                              : () => Navigator.pop(dialogContext, false),
                        ),
                        FxButton(
                          label: saving
                              ? '保存中…'
                              : existing == null
                                  ? '创建'
                                  : '保存',
                          onPressed: saving
                              ? null
                              : () async {
                                  final name = nameController.text.trim();
                                  if (name.isEmpty) {
                                    setDialogState(() => error = '请输入清单名称');
                                    return;
                                  }
                                  setDialogState(() {
                                    saving = true;
                                    error = null;
                                  });
                                  try {
                                    if (existing == null) {
                                      await DataService().createList(
                                        name: name,
                                        icon: selectedIcon,
                                        color: selectedColor,
                                      );
                                    } else {
                                      await DataService().updateList(
                                        localId: existing.id,
                                        serverId: existing.serverId,
                                        name: name,
                                        icon: selectedIcon,
                                        color: selectedColor,
                                      );
                                    }
                                    if (dialogContext.mounted) {
                                      Navigator.pop(dialogContext, true);
                                    }
                                  } catch (e) {
                                    setDialogState(() {
                                      saving = false;
                                      error = '保存失败：$e';
                                    });
                                  }
                                },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    nameController.dispose();
    if (saved == true) await _loadLists();
  }

  Widget _fieldLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: SlowlightTypography.caption(context).copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );

  Future<void> _deleteList(TodoList list) async {
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '删除清单',
      content: '确定删除「${list.name}」？该清单下的任务也会被删除。',
      confirmText: '删除',
      destructive: true,
    );
    if (confirmed != true) return;
    try {
      await DataService().deleteList(list.id, list.serverId);
      await _loadLists();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _loadLists,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 72),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      FxChip(
                        label: '${_lists.length} 个清单',
                        variant: FxChipVariant.secondary,
                      ),
                      FxButton(
                        label: '新建清单',
                        icon: LucideIcons.plus,
                        size: FxButtonSize.sm,
                        onPressed: () => _showEditor(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_lists.isEmpty)
                    FxEmptyState(
                      emoji: '📁',
                      title: '还没有清单',
                      subtitle: '用清单把不同方向的任务分开',
                      action: FxButton(
                        label: '创建第一个清单',
                        variant: FxButtonVariant.outline,
                        size: FxButtonSize.sm,
                        onPressed: () => _showEditor(),
                      ),
                    )
                  else
                    FxCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      expanded: true,
                      child: Column(
                        children: _lists.map((list) {
                          final color = ColorUtils.safeParse(list.color);
                          final count = _taskCountFor(list);
                          return Container(
                            constraints: const BoxConstraints(minHeight: 60),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: .10),
                                    borderRadius:
                                        BorderRadius.circular(AppTheme.radiusMd),
                                  ),
                                  child: Text(
                                    list.icon,
                                    style: const TextStyle(fontSize: 17),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        list.name,
                                        style:
                                            SlowlightTypography.body(context)
                                                .copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (list.isInbox)
                                        Text(
                                          '默认收集箱',
                                          style: SlowlightTypography.caption(
                                            context,
                                          ).copyWith(
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '$count 条',
                                  style: SlowlightTypography.caption(context)
                                      .copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                FxIconButton(
                                  tooltip: '编辑',
                                  onPressed: () => _showEditor(list),
                                  icon: LucideIcons.pencil,
                                  iconSize: 17,
                                ),
                                if (!list.isInbox)
                                  FxIconButton(
                                    tooltip: '删除',
                                    onPressed: () => _deleteList(list),
                                    icon: LucideIcons.trash2,
                                    iconSize: 17,
                                  ),
                              ],
                            ),
                          );
                        }).toList(growable: false),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
