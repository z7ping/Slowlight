import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/observation_tag.dart';
import '../repositories/observation_tag_repository.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../utils/color_utils.dart';

/// 标签管理页。历史标签的 dimension_key 只保留在兼容数据层。
class SystemTagScreen extends StatefulWidget {
  // Optional test seam; production uses the same ObservationTagRepository.
  final ObservationTagRepository? repository;
  final ValueListenable<int>? createRequest;

  const SystemTagScreen({super.key, this.repository, this.createRequest});

  @override
  State<SystemTagScreen> createState() => _SystemTagScreenState();
}

class _SystemTagScreenState extends State<SystemTagScreen> {
  late final ObservationTagRepository _repository;
  bool _loading = true;
  bool _hasLoaded = false;
  int _loadVersion = 0;
  bool _deletingTag = false;
  String? _error;
  List<ObservationTag> _tags = const [];
  Map<int, ObservationTagUsage> _usage = const {};
  bool _usageLoading = false;
  bool _usageFailed = false;

  static const _presetEmojis = [
    '🏃',
    '💪',
    '🧘',
    '🧠',
    '📚',
    '✍️',
    '💡',
    '🎯',
    '💼',
    '🏠',
    '👨‍👩‍👧',
    '🎨',
    '🎵',
    '🌱',
    '🔧',
    '📊',
  ];
  static const _presetColors = [
    '#52C41A',
    '#1890FF',
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
    _repository = widget.repository ?? ObservationTagRepository();
    widget.createRequest?.addListener(_createFromHeader);
    _load();
  }

  void _createFromHeader() {
    if (mounted) unawaited(_editTag());
  }

  @override
  void didUpdateWidget(covariant SystemTagScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.createRequest != widget.createRequest) {
      oldWidget.createRequest?.removeListener(_createFromHeader);
      widget.createRequest?.addListener(_createFromHeader);
    }
  }

  @override
  void dispose() {
    widget.createRequest?.removeListener(_createFromHeader);
    super.dispose();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    if (mounted) {
      setState(() {
        _loading = !_hasLoaded;
        _error = null;
        _usage = const {};
        _usageLoading = false;
        _usageFailed = false;
      });
    }
    try {
      final tags = await _repository.getAll();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _tags = tags;
        _loading = false;
        _hasLoaded = true;
        _error = null;
      });
      unawaited(_loadUsage(version, tags));
    } catch (e) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        // Preserve previously confirmed tags and their edit controls.
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadUsage(int version, List<ObservationTag> tags) async {
    if (!mounted || version != _loadVersion || _usageLoading) return;
    setState(() {
      _usageLoading = true;
      _usageFailed = false;
    });
    try {
      final result = await _repository.getAssociationUsage(tags);
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _usage = result;
        _usageLoading = false;
        _usageFailed = result.length < tags.length;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _usageLoading = false;
        _usageFailed = true;
      });
    }
  }

  String _usageLabel(ObservationTag tag) {
    final impact = _usage[tag.id];
    if (impact == null) return _usageLoading ? '关联读取中…' : '关联未核对';
    final total = impact.tasks + impact.habits +
        impact.sessions + impact.reflections;
    return '关联影响 ${total} 条 · 任务 ${impact.tasks} / 习惯 ${impact.habits} / '
        '专注 ${impact.sessions} / 观察 ${impact.reflections}';
  }

  List<_ObservationTagGroup> _groups() => _tags.isEmpty
      ? const []
      : [_ObservationTagGroup(label: '', tags: _tags)];

  Widget _card({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    Color? color,
  }) {
    return FxCard(
      padding: padding,
      color: color ?? fxSurface(context),
      borderRadius: SlowlightRadius.lg,
      border: Border.all(color: fxBorder(context)),
      expanded: true,
      child: child,
    );
  }

  Widget _chip(String label, {bool accent = false}) {
    final theme = Theme.of(context);
    return FxChip(
      label: label,
      backgroundColor:
          accent
              ? activePalette.accent.withValues(alpha: .12)
              : fxSubtleSurface(context),
      foregroundColor:
          accent ? activePalette.accent : theme.colorScheme.onSurfaceVariant,
      borderRadius: SlowlightRadius.pill,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_hasLoaded) {
      return const Center(child: FxCircularProgress());
    }
    if (_error != null && !_hasLoaded) return _errorView();

    final groups = _groups();
    return FxRefresh(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.createRequest != null
            ? const EdgeInsets.fromLTRB(16, 12, 16, 48)
            : const EdgeInsets.fromLTRB(20, 18, 20, 72),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.createRequest != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(children: [
                        Expanded(child: Text(
                          '${_tags.length} 个标签',
                          style: SlowlightTypography.secondary(context),
                        )),
                        Text('跨记录分类使用',
                          style: SlowlightTypography.caption(context)),
                      ]),
                    )
                  else
                    FxActionBar(
                    leading: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('观察标签',
                            style: SlowlightTypography.sectionTitle(context)),
                        _chip('${_tags.length} 个标签'),
                      ],
                    ),
                    actions: [
                      FxButton(
                        label: '新建标签',
                        icon: LucideIcons.plus,
                        size: FxButtonSize.sm,
                        onPressed: () => _editTag(),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    FxCard(
                      padding: const EdgeInsets.all(12),
                      expanded: true,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '标签刷新未确认，以下仍为上次已载入的标签。',
                              style: SlowlightTypography.secondary(context),
                            ),
                          ),
                          FxButton(
                            label: '重试',
                            size: FxButtonSize.sm,
                            variant: FxButtonVariant.ghost,
                            onPressed: _load,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_usageFailed && !_usageLoading) ...[
                    FxCard(
                      padding: const EdgeInsets.all(12),
                      expanded: true,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '标签关联数量未全部核对，标签本身仍可管理。',
                              style: SlowlightTypography.secondary(context),
                            ),
                          ),
                          FxButton(
                            label: '重试关联',
                            size: FxButtonSize.sm,
                            variant: FxButtonVariant.ghost,
                            onPressed: () => _loadUsage(_loadVersion, _tags),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (_tags.isEmpty)
                    FxEmptyState(
                      icon: LucideIcons.tag,
                      title: '还没有标签',
                      subtitle: '使用标签整理记录，之后可以按标签查看相关内容',
                    )
                  else
                    ...List.generate(groups.length, (index) {
                      final group = groups[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index == groups.length - 1 ? 0 : 12,
                        ),
                        child: _tagGroup(group),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tagGroup(_ObservationTagGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        _card(
          padding: EdgeInsets.symmetric(horizontal: widget.createRequest == null ? 12 : 0),
          child: Column(
            children: group.tags.map(_tagRow).toList(growable: false),
          ),
        ),
      ],
    );
  }

  Widget _tagGlyph(String value) {
    final glyph = switch (value) {
      '🏃' || '💪' || '🧘' => LucideIcons.timer,
      '🧠' || '📚' => LucideIcons.bookOpen,
      '🎯' || '✍️' => LucideIcons.flag,
      '💼' => LucideIcons.folder,
      '🏠' || '👨‍👩‍👧' => LucideIcons.sun,
      '💡' || '🌱' => LucideIcons.sun,
      _ => null,
    };
    return glyph == null
        ? Text(value, style: const TextStyle(fontSize: SlowlightTypography.bodySize))
        : Icon(glyph, size: SlowlightIconSize.lg,
            color: activePalette.accent);
  }

  Widget _tagRow(ObservationTag tag) {
    if (widget.createRequest != null) {
      final color = ColorUtils.safeParse(tag.color);
      final usage = _usage[tag.id];
      final summary = usage == null
          ? (_usageLoading ? '关联读取中…' : '关联未核对')
          : [
              if (usage.tasks > 0) '任务 ${usage.tasks}',
              if (usage.habits > 0) '习惯 ${usage.habits}',
              if (usage.sessions > 0) '专注 ${usage.sessions}',
              if (usage.reflections > 0) '观察 ${usage.reflections}',
            ].join(' · ');
      return FxListTile(
        key: ValueKey(tag.id),
        onTap: () => _editTag(tag),
        density: FxListTileDensity.detailed,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        showDivider: true,
        leading: Container(
          width: 40, height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(SlowlightRadius.md),
          ),
          child: _tagGlyph(tag.icon),
        ),
        title: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('#${tag.name}',
              style: SlowlightTypography.body(context).copyWith(
                fontWeight: FontWeight.w600,
              )),
            if (tag.isDefault) _chip('默认'),
          ],
        ),
        subtitle: summary.isEmpty ? '暂无已载入关联' : summary,
        trailing: FxMenu<int>(
          tooltip: '管理标签',
          onSelected: (action) {
            if (action == 0) {
              unawaited(_editTag(tag));
            } else {
              unawaited(_confirmDelete(tag));
            }
          },
          itemBuilder: (_) => [
            const FxMenuItem(value: 0, child: Text('编辑标签')),
            if (!tag.isDefault)
              const FxMenuItem(value: 1, child: Text('删除标签')),
          ],
          child: const SizedBox(
            width: 44, height: 44,
            child: Center(child: Icon(LucideIcons.menu, size: 18)),
          ),
        ),
      );
    }
    final theme = Theme.of(context);
    final color = ColorUtils.safeParse(tag.color);
    return FxInkWell(
      onTap: () => _editTag(tag),
      borderRadius: BorderRadius.circular(SlowlightRadius.md),
      child: Container(
      key: ValueKey(tag.id),
      constraints: const BoxConstraints(minHeight: 58),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: fxDivider(context))),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(SlowlightRadius.md),
            ),
            child: Text(tag.icon, style: const TextStyle(fontSize: SlowlightTypography.bodySize)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '#${tag.name}',
                      style: SlowlightTypography.secondary(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (tag.isDefault) _chip('默认'),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _usageLabel(tag),
                  style: SlowlightTypography.caption(context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          FxIconButton(
            tooltip: '编辑',
            onPressed: () => _editTag(tag),
            icon: LucideIcons.pencil,
          ),
          FxIconButton(
            tooltip: tag.isDefault ? '默认标签不可删除' : '删除',
            onPressed: tag.isDefault ? null : () => _confirmDelete(tag),
            icon: LucideIcons.trash2,
            foregroundColor:
                tag.isDefault
                    ? theme.colorScheme.onSurfaceVariant.withValues(alpha: .35)
                    : theme.colorScheme.error,
          ),
        ],
      ),
      ),
    );
  }

  Widget _errorView() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.circleAlert,
            size: 32,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 10),
          const Text('标签加载失败'),
          const SizedBox(height: 6),
          Text(
            _error!,
            style: SlowlightTypography.caption(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          FxButton(
            label: '重试',
            variant: FxButtonVariant.outline,
            onPressed: _load,
          ),
        ],
      ),
    );
  }

  Future<void> _editTag([ObservationTag? existing]) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    var icon = existing?.icon ?? _presetEmojis.first;
    var color = existing?.color ?? _presetColors.first;
    String? dimensionKey = existing?.dimensionKey;
    var saving = false;
    var writeUnknown = false;
    String? error;

    final saved = await FxDialog.show<bool>(
      context: context,
      title: existing == null ? '新建标签' : '编辑标签',
      width: 540,
      child: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final theme = Theme.of(dialogContext);
          Widget selectableChip({
            required String label,
            required bool selected,
            required VoidCallback onTap,
          }) {
            return FxChip(
              label: label,
              onTap: saving || writeUnknown ? null : onTap,
              backgroundColor:
                  selected
                      ? activePalette.accent.withValues(alpha: .12)
                      : fxSubtleSurface(dialogContext),
              foregroundColor:
                  selected
                      ? activePalette.accent
                      : theme.colorScheme.onSurfaceVariant,
              borderColor:
                  selected
                      ? activePalette.accent.withValues(alpha: .35)
                      : theme.colorScheme.outlineVariant,
              borderRadius: SlowlightRadius.pill,
            );
          }

          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 620),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FxInput(
                    controller: nameController,
                    autofocus: true,
                    enabled: !saving && !writeUnknown,
                    placeholder: '例如：分心、心流、精力低谷',
                  ),
                  if (existing != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _usageLabel(existing),
                      style: SlowlightTypography.caption(dialogContext),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _dialogLabel(dialogContext, '图标'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _presetEmojis.map((item) {
                      final selected = item == icon;
                      if (widget.createRequest == null) {
                        return selectableChip(
                          label: item,
                          selected: selected,
                          onTap: () => setDialogState(() => icon = item),
                        );
                      }
                      return FxInkWell(
                        onTap: saving || writeUnknown ? null :
                            () => setDialogState(() => icon = item),
                        borderRadius: BorderRadius.circular(SlowlightRadius.md),
                        child: Container(
                          width: 44, height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? activePalette.accent.withValues(alpha: .12)
                                : Colors.transparent,
                            border: Border.all(
                              color: selected
                                  ? activePalette.accent
                                  : theme.colorScheme.outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(SlowlightRadius.md),
                          ),
                          child: _tagGlyph(item),
                        ),
                      );
                    }).toList(growable: false),
                  ),
                  const SizedBox(height: 14),
                  _dialogLabel(dialogContext, '颜色'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _presetColors
                        .map((item) {
                          final selected =
                              item.toLowerCase() == color.toLowerCase();
                          return FxInkWell(
                            onTap:
                                saving || writeUnknown
                                    ? null
                                    : () => setDialogState(() => color = item),
                            borderRadius: BorderRadius.circular(22),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: ColorUtils.safeParse(item),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color:
                                          selected
                                              ? theme.colorScheme.onSurface
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
                                : () => Navigator.of(dialogContext).pop(false),
                      ),
                      FxButton(
                        label: saving ? '保存中…' : '保存',
                        onPressed:
                            saving || writeUnknown
                                ? null
                                : () async {
                                  final name = nameController.text.trim();
                                  if (name.isEmpty) {
                                    setDialogState(() => error = '标签名称不能为空');
                                    return;
                                  }
                                  if (_tags.any((tag) =>
                                      tag.name == name && tag.id != existing?.id)) {
                                    setDialogState(() => error = '标签名称已存在');
                                    return;
                                  }
                                  setDialogState(() {
                                    saving = true;
                                    error = null;
                                  });
                                  try {
                                    if (existing == null) {
                                      await _repository.create(
                                        name: name,
                                        icon: icon,
                                        color: color,
                                        dimensionKey: dimensionKey,
                                      );
                                    } else {
                                      await _repository.update(
                                        existing,
                                        name: name,
                                        icon: icon,
                                        color: color,
                                        dimensionKey: dimensionKey,
                                      );
                                    }
                                    if (dialogContext.mounted) {
                                      Navigator.of(dialogContext).pop(true);
                                    }
                                  } catch (e) {
                                    if (!dialogContext.mounted) return;
                                    setDialogState(() {
                                      saving = false;
                                      writeUnknown = true;
                                      error = '保存回执未确认，请关闭后重新读取标签，避免重复写入：$e';
                                    });
                                  }
                                },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    nameController.dispose();
    if (saved == true) await _load();
  }

  Widget _dialogLabel(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: SlowlightTypography.caption(context).copyWith(
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Future<void> _confirmDelete(ObservationTag tag) async {
    if (tag.isDefault || _deletingTag) return;
    final version = _loadVersion;
    _deletingTag = true;
    try {
      final impact = await _repository.getDeletionImpact(tag);
      if (!mounted || version != _loadVersion ||
          !_tags.any((item) => item.id == tag.id)) return;
      if (impact == null) {
        FxNotice.showContent(
          context,
          const Text('标签关联数量未确认，已阻止删除，请重试核对。'),
        );
        return;
      }
      final detail = '已核对将解除的关联：任务 ${impact.tasks} 项、习惯 ${impact.habits} 项、'
          '专注 ${impact.sessions} 项、观察/回应 ${impact.reflections} 项。'
          '删除只解除关联，不删除原有记录。';
      final confirmed = await FxDialog.confirm(
        context: context,
        title: '删除标签并解除关联？',
        content: '删除「${tag.name}」？$detail',
        confirmText: '删除标签',
        cancelText: '保留标签',
        destructive: true,
        barrierDismissible: false,
      );
      if (confirmed != true || !mounted || version != _loadVersion) return;
      final undo = await _repository.deleteWithUndo(
        tag, expectedImpact: impact,
      );
      if (mounted) {
        await _load();
        if (mounted) {
          FxNotice.success(
            context, '标签已删除，原记录仍保留',
            action: FxNoticeAction(
              label: '撤销',
              onPressed: () => unawaited(_undoDeletedTag(undo)),
            ),
            duration: const Duration(seconds: 8),
          );
        }
      }
    } catch (error) {
      if (!mounted) return;
      FxNotice.showContent(
        context,
        Text('无法确认标签删除影响或删除失败，标签未被确认删除：$error'),
      );
    } finally {
      _deletingTag = false;
    }
  }

  Future<void> _undoDeletedTag(ObservationTagDeletionUndo undo) async {
    try {
      await undo.restore();
      if (mounted) {
        await _load();
        if (mounted) FxNotice.success(context, '原标签及关联已恢复');
      }
    } catch (error) {
      if (mounted) {
        FxNotice.errorWithDetails(context, '标签撤销结果未确认', '$error');
      }
    }
  }

}

class _ObservationTagGroup {
  final String label;
  final List<ObservationTag> tags;

  const _ObservationTagGroup({required this.label, required this.tags});
}
