import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/task.dart';
import '../models/todo_list.dart';
import '../services/data_service.dart';
import '../services/list_delete_undo_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../utils/color_utils.dart';

/// 清单管理：作为「更多工具」中的一级内容页嵌入主壳，不再叠加第二层 AppBar。
class ListManageScreen extends StatefulWidget {
  // Source-level test seams; production still uses DataService.
  final Future<List<TodoList>> Function()? listsLoader;
  final Future<List<Task>> Function()? tasksLoader;

  const ListManageScreen({
    super.key,
    this.listsLoader,
    this.tasksLoader,
  });

  @override
  State<ListManageScreen> createState() => _ListManageScreenState();
}

class _ListManageScreenState extends State<ListManageScreen> {
  bool _loading = true;
  bool _hasLoaded = false;
  bool _loadFailed = false;
  bool _taskCountConfirmed = false;
  bool _taskCountLoading = false;
  bool _taskCountFailed = false;
  int _loadVersion = 0;
  List<TodoList> _lists = const [];
  List<Task> _tasks = const [];

  static const _presetIcons = [
    '📁',
    '💼',
    '🏠',
    '🎯',
    '💡',
    '📚',
    '🎨',
    '🔧',
    '❤️',
    '🌟',
    '🌱',
    '📊',
  ];
  static const _presetColors = [
    '#1890FF',
    '#52C41A',
    '#FAAD14',
    '#FF6B6B',
    '#722ED1',
    '#13C2C2',
    '#EB2F96',
    '#FA8C16',
  ];

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  Future<void> _loadLists() async {
    final version = ++_loadVersion;
    if (mounted) {
      setState(() {
        // List management is usable independently of task count reporting.
        _loading = !_hasLoaded;
        _loadFailed = false;
      });
    }
    try {
      final lists = await (widget.listsLoader?.call() ??
          DataService().getLists());
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _lists = lists;
        _loading = false;
        _hasLoaded = true;
        _loadFailed = false;
        // A new list snapshot requires independently checked task totals.
        _taskCountConfirmed = false;
        _taskCountFailed = false;
        _taskCountLoading = true;
      });
      unawaited(_loadTaskCounts(version));
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
      // Keep the previously confirmed list rows; never show a false empty.
    }
  }

  Future<void> _loadTaskCounts(int version) async {
    try {
      final tasks = await (widget.tasksLoader?.call() ??
          DataService().getAllTasks());
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _tasks = tasks;
        _taskCountConfirmed = true;
        _taskCountLoading = false;
        _taskCountFailed = false;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _taskCountConfirmed = false;
        _taskCountLoading = false;
        _taskCountFailed = true;
      });
    }
  }

  Future<void> _retryTaskCounts() async {
    if (_taskCountLoading) return;
    setState(() {
      _taskCountLoading = true;
      _taskCountFailed = false;
    });
    await _loadTaskCounts(_loadVersion);
  }

  int _taskCountFor(TodoList list) =>
      _tasks.where((task) => task.listId == list.id).length;

  Future<void> _showListDetails(TodoList list) async {
    final version = _loadVersion;
    final confirmed = _taskCountConfirmed;
    final tasks = confirmed
        ? _tasks.where((task) => task.listId == list.id).toList(growable: false)
        : <Task>[];
    final edit = await FxDialog.show<bool>(
      context: context,
      title: list.name,
      child: Builder(
        builder: (dialogContext) => SizedBox(
          width: MediaQuery.sizeOf(dialogContext).width < 454
              ? MediaQuery.sizeOf(dialogContext).width - 64
              : 390,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                confirmed ? '${tasks.length} 条任务' : '任务数量待核对',
                style: SlowlightTypography.secondary(dialogContext),
              ),
              const SizedBox(height: SlowlightSpacing.md),
              if (!confirmed)
                Text(
                  '当前只确认了清单，无法展示完整任务列表；请返回后重试任务数。',
                  style: SlowlightTypography.secondary(dialogContext),
                )
              else if (tasks.isEmpty)
                Text('暂无任务',
                    style: SlowlightTypography.secondary(dialogContext))
              else
                SizedBox(
                  height: tasks.length > 5 ? 220 : tasks.length * 44.0,
                  child: ListView.builder(
                    key: const ValueKey('lists.detail.tasks'),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 32),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              task.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: SlowlightTypography.secondary(context),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: SlowlightSpacing.xl),
              FxDialogActions(
                actions: [
                  if (!list.isInbox)
                    FxButton(
                      label: '编辑清单',
                      variant: FxButtonVariant.outline,
                      onPressed: () => Navigator.of(
                        dialogContext, rootNavigator: true,
                      ).pop(true),
                    ),
                  FxButton(
                    label: '关闭',
                    variant: FxButtonVariant.secondary,
                    onPressed: () => Navigator.of(
                      dialogContext, rootNavigator: true,
                    ).pop(false),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (edit == true && mounted && version == _loadVersion &&
        !list.isInbox) {
      await _showEditor(list);
    }
  }

  Future<void> _showEditor([TodoList? existing]) async {
    if (existing?.isInbox == true) return;
    final nameController = TextEditingController(text: existing?.name ?? '');
    var selectedIcon = existing?.icon ?? _presetIcons.first;
    var selectedColor = existing?.color ?? _presetColors.first;
    var saving = false;
    var writeUnknown = false;
    String? error;

    final saved = await FxDialog.raw<bool>(
      context: context,
      barrierColor: FxDialog.barrierColor,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              final theme = Theme.of(dialogContext);
              return FxDialogSurface(
                backgroundColor: theme.colorScheme.surface,
                surfaceTintColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SlowlightRadius.xl),
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
                        Text(
                          existing == null ? '新建清单' : '编辑清单',
                          style: SlowlightTypography.cardTitle(dialogContext),
                        ),
                        const SizedBox(height: 8),
                        FxInput(
                          controller: nameController,
                          autofocus: true,
                          enabled: !saving && !writeUnknown,
                          placeholder: '清单名称',
                          style: SlowlightTypography.body(dialogContext),
                        ),
                        const SizedBox(height: 14),
                        _fieldLabel(dialogContext, '图标'),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _presetIcons
                              .map((icon) {
                                final selected = icon == selectedIcon;
                                return FxInkWell(
                                  onTap:
                                      saving || writeUnknown
                                          ? null
                                          : () => setDialogState(
                                            () => selectedIcon = icon,
                                          ),
                                  borderRadius: BorderRadius.circular(
                                    SlowlightRadius.md,
                                  ),
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color:
                                          selected
                                              ? activePalette.accent.withValues(
                                                alpha: .12,
                                              )
                                              : Colors.transparent,
                                      borderRadius: BorderRadius.circular(
                                        SlowlightRadius.md,
                                      ),
                                      border: Border.all(
                                        color:
                                            selected
                                                ? activePalette.accent
                                                : theme
                                                    .colorScheme
                                                    .outlineVariant,
                                      ),
                                    ),
                                    child: Text(
                                      icon,
                                      style: const TextStyle(
                                        fontSize: SlowlightIconSize.md,
                                      ),
                                    ),
                                  ),
                                );
                              })
                              .toList(growable: false),
                        ),
                        const SizedBox(height: 14),
                        _fieldLabel(dialogContext, '颜色'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: _presetColors
                              .map((value) {
                                final selected = value == selectedColor;
                                final color = ColorUtils.safeParse(value);
                                return FxInkWell(
                                  onTap:
                                      saving || writeUnknown
                                          ? null
                                          : () => setDialogState(
                                            () => selectedColor = value,
                                          ),
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
                                            color:
                                                selected
                                                    ? theme
                                                        .colorScheme
                                                        .onSurface
                                                    : Colors.transparent,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              })
                              .toList(growable: false),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            error!,
                            style: SlowlightTypography.caption(
                              dialogContext,
                            ).copyWith(color: theme.colorScheme.error),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FxDialogActions(
                          actions: [
                            FxButton(
                              label: '取消',
                              variant: FxButtonVariant.outline,
                              onPressed:
                                  saving
                                      ? null
                                      : () =>
                                          Navigator.pop(dialogContext, false),
                            ),
                            FxButton(
                              label:
                                  saving
                                      ? '保存中…'
                                      : existing == null
                                      ? '创建'
                                      : '保存',
                              onPressed:
                                  saving || writeUnknown
                                      ? null
                                      : () async {
                                        final name = nameController.text.trim();
                                        if (name.isEmpty) {
                                          setDialogState(
                                            () => error = '请输入清单名称',
                                          );
                                          return;
                                        }
                                        if (_lists.any((item) =>
                                            item.name == name &&
                                            item.id != existing?.id)) {
                                          setDialogState(
                                            () => error = '清单名称不能重复',
                                          );
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
                                          if (!dialogContext.mounted) return;
                                          setDialogState(() {
                                            saving = false;
                                            // Network errors do not prove that
                                            // the remote write was rejected.
                                            writeUnknown = true;
                                            error = '保存结果尚未确认，请关闭窗口并刷新核对：$e';
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
    if (!_taskCountConfirmed) {
      FxNotice.showContent(
        context,
        const Text('请先确认任务数量后再删除清单，避免误删未知任务'),
      );
      return;
    }

    // A cached list count is not enough for an irreversible delete.
    // Recheck the affected tasks immediately before opening confirmation.
    final version = _loadVersion;
    late final List<Task> currentTasks;
    try {
      currentTasks = await (widget.tasksLoader?.call() ??
          DataService().getAllTasks());
    } catch (_) {
      if (mounted) {
        FxNotice.showContent(
          context,
          const Text('无法核对删除影响范围，未执行删除，请稍后重试'),
        );
      }
      return;
    }
    if (!mounted || version != _loadVersion ||
        !_lists.any((item) => item.id == list.id)) return;
    final affected = currentTasks
        .where((task) => task.listId == list.id)
        .toList(growable: false);
    final completed = affected.where((task) => task.isCompleted).length;
    setState(() => _tasks = currentTasks);

    final confirmed = await FxDialog.show<bool>(
      context: context,
      title: '删除清单及其任务？',
      barrierDismissible: false,
      showCloseButton: false,
      child: Builder(
        builder: (dialogContext) => SizedBox(
          width: MediaQuery.sizeOf(dialogContext).width < 454
              ? MediaQuery.sizeOf(dialogContext).width - 64
              : 390,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '删除「${list.name}」将同时删除 ${affected.length} 项任务'
                '（其中已完成 $completed 项），并影响今天、回顾和统计。',
                style: SlowlightTypography.secondary(dialogContext),
              ),
              const SizedBox(height: SlowlightSpacing.md),
              if (affected.isNotEmpty)
                SizedBox(
                  height: affected.length > 4 ? 176 : affected.length * 44.0,
                  child: ListView.builder(
                    key: const ValueKey('lists.delete.affectedTasks'),
                    itemCount: affected.length,
                    itemBuilder: (context, index) {
                      final task = affected[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 32),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${task.title} · ${task.isCompleted ? '已完成' : '未完成'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: SlowlightTypography.secondary(context),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                )
              else
                Text('该清单暂无任务。',
                    style: SlowlightTypography.secondary(dialogContext)),
              const SizedBox(height: SlowlightSpacing.xl),
              FxDialogActions(
                actions: [
                  FxButton(
                    label: '保留清单',
                    variant: FxButtonVariant.outline,
                    onPressed: () => Navigator.of(
                      dialogContext, rootNavigator: true,
                    ).pop(false),
                  ),
                  FxButton(
                    label: '删除清单与任务',
                    variant: FxButtonVariant.destructive,
                    onPressed: () => Navigator.of(
                      dialogContext, rootNavigator: true,
                    ).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final undo = await ListDeleteUndoService().delete(
        localId: list.id,
        serverId: list.serverId,
        expectedTaskCount: affected.length,
      );
      await _loadLists();
      if (mounted) {
        FxNotice.success(
          context, '清单已删除',
          action: FxNoticeAction(
            label: '撤销',
            onPressed: () => unawaited(_undoDeletedList(undo)),
          ),
          duration: const Duration(seconds: 8),
        );
      }
    } catch (e) {
      if (!mounted) return;
      FxNotice.showContent(context, Text('删除失败：$e'));
    }
  }

  Future<void> _undoDeletedList(ListDeletionUndo undo) async {
    try {
      await undo.restore();
      if (mounted) {
        await _loadLists();
        if (mounted) FxNotice.success(context, '原清单及其任务已恢复');
      }
    } catch (error) {
      if (mounted) {
        FxNotice.errorWithDetails(context, '清单撤销结果未确认', '$error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: FxCircularProgress());
    if (_loadFailed && !_hasLoaded) {
      return Center(
        child: FxEmptyState(
          icon: LucideIcons.triangleAlert,
          title: '清单加载失败',
          subtitle: '数据未能读取，请检查连接后重试。',
          action: FxButton(
            label: '重新加载',
            variant: FxButtonVariant.secondary,
            onPressed: _loadLists,
          ),
        ),
      );
    }
    final theme = Theme.of(context);
    return FxRefresh(
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
                  FxActionBar(
                    leading: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '清单管理',
                          style: SlowlightTypography.sectionTitle(context),
                        ),
                        FxChip(
                          label: '${_lists.length} 个清单',
                          variant: FxChipVariant.secondary,
                        ),
                      ],
                    ),
                    actions: [
                      FxButton(
                        label: '新建清单',
                        icon: LucideIcons.plus,
                        size: FxButtonSize.sm,
                        onPressed: () => _showEditor(),
                      ),
                    ],
                  ),
                  if (_loadFailed || _taskCountFailed) ...[
                    FxCard(
                      padding: const EdgeInsets.all(12),
                      expanded: true,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _loadFailed
                                  ? '清单刷新未确认，继续展示上次已载入的清单。'
                                  : '任务数量未确认，清单仍可创建和编辑；删除请先重试。',
                              style: SlowlightTypography.secondary(context),
                            ),
                          ),
                          FxButton(
                            label: '重新加载',
                            size: FxButtonSize.sm,
                            variant: FxButtonVariant.ghost,
                            onPressed: _loadFailed ? _loadLists : _retryTaskCounts,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 14),
                  if (_lists.isEmpty)
                    FxEmptyState(
                      icon: LucideIcons.folder,
                      title: '还没有清单',
                      subtitle: '用清单把不同方向的任务分开',
                    )
                  else
                    FxCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      expanded: true,
                      child: Column(
                        children: _lists.map((list) {
                          final color = ColorUtils.safeParse(list.color);
                          final count = _taskCountFor(list);
                          return FxListTile(
                            onTap: () => _showListDetails(list),
                            density: list.isInbox
                                ? FxListTileDensity.detailed
                                : FxListTileDensity.compact,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            showDivider: true,
                            leading: Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(
                                  SlowlightRadius.md,
                                ),
                              ),
                              child: Text(
                                list.icon,
                                style: const TextStyle(
                                  fontSize: SlowlightIconSize.md,
                                ),
                              ),
                            ),
                            title: list.name,
                            titleTextStyle: SlowlightTypography.secondary(
                              context,
                            ).copyWith(fontWeight: FontWeight.w600),
                            subtitle: list.isInbox ? '默认收集箱' : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _taskCountConfirmed ? '$count 条' : '— 条',
                                  style: SlowlightTypography.caption(
                                    context,
                                  ).copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                if (!list.isInbox)
                                  FxIconButton(
                                    tooltip: '编辑',
                                    onPressed: () => _showEditor(list),
                                    icon: LucideIcons.pencil,
                                    iconSize: SlowlightIconSize.md,
                                  ),
                                if (!list.isInbox)
                                  FxIconButton(
                                    tooltip: '删除',
                                    onPressed: _taskCountConfirmed
                                        ? () => _deleteList(list)
                                        : null,
                                    icon: LucideIcons.trash2,
                                    iconSize: SlowlightIconSize.md,
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
