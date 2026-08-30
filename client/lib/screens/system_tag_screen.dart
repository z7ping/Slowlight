import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/dimension.dart';
import '../models/observation_tag.dart';
import '../repositories/observation_tag_repository.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../utils/color_utils.dart';

/// 用户管理的是“观察标签”，不是固定的四维度本身。
class SystemTagScreen extends StatefulWidget {
  const SystemTagScreen({super.key});

  @override
  State<SystemTagScreen> createState() => _SystemTagScreenState();
}

class _SystemTagScreenState extends State<SystemTagScreen> {
  final _repository = ObservationTagRepository();
  bool _loading = true;
  String? _error;
  List<ObservationTag> _tags = const [];

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
    _load();
  }

  Future<void> _load() async {
    try {
      final tags = await _repository.getAll();
      if (!mounted) return;
      setState(() {
        _tags = tags;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<_ObservationTagGroup> _groups() {
    final groups = <_ObservationTagGroup>[];
    for (final dimension in DimensionCatalog.all) {
      final tags = _tags
          .where((tag) => tag.dimensionKey == dimension.keyValue)
          .toList(growable: false);
      if (tags.isNotEmpty) {
        groups.add(
          _ObservationTagGroup(
            label: '${dimension.icon} ${dimension.name}',
            tags: tags,
          ),
        );
      }
    }
    final unclassified = _tags
        .where((tag) => tag.dimensionKey == null || tag.dimensionKey!.isEmpty)
        .toList(growable: false);
    if (unclassified.isNotEmpty) {
      groups.add(_ObservationTagGroup(label: '未归类 · 仅分析', tags: unclassified));
    }
    return groups;
  }

  Widget _card({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
    Color? color,
  }) {
    final theme = Theme.of(context);
    return FxCard(
      padding: padding,
      color: color ?? fxSurface(context),
      borderRadius: AppTheme.radiusLg,
      border: Border.all(color: fxBorder(context)),
      boxShadow:
          theme.brightness == Brightness.light ? AppTheme.cardShadow : null,
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
      borderRadius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: FxCircularProgress());
    if (_error != null) return _errorView();

    final groups = _groups();
    return FxRefresh(
      onRefresh: _load,
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
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      _chip('${_tags.length} 个标签'),
                      FxButton(
                        label: '新建标签',
                        icon: LucideIcons.plus,
                        size: FxButtonSize.sm,
                        onPressed: () => _editTag(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _explanationCard(),
                  const SizedBox(height: 12),
                  if (_tags.isEmpty)
                    FxEmptyState(
                      emoji: '🏷️',
                      title: '还没有观察标签',
                      subtitle: '标签用于分类事实；不归属维度时只参与分类与分析',
                      action: FxButton(
                        label: '创建标签',
                        variant: FxButtonVariant.outline,
                        size: FxButtonSize.sm,
                        onPressed: () => _editTag(),
                      ),
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

  Widget _explanationCard() {
    final theme = Theme.of(context);
    return _card(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '标签和维度是两回事',
            style: SlowlightTypography.secondary(
              context,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            '身体、认知、产出、关系是固定长期坐标；标签是你自己的分类方式。标签可以归属某个维度，也可以保持“未归类 · 仅分析”。',
            style: SlowlightTypography.secondary(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: DimensionCatalog.all
                .map((item) => _chip('${item.icon} ${item.name}'))
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _tagGroup(_ObservationTagGroup group) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
          child: Text(
            group.label,
            style: SlowlightTypography.caption(context).copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _card(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: group.tags.map(_tagRow).toList(growable: false),
          ),
        ),
      ],
    );
  }

  Widget _tagRow(ObservationTag tag) {
    final theme = Theme.of(context);
    final color = ColorUtils.safeParse(tag.color);
    return Container(
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
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Text(tag.icon, style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
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
          const Text('观察标签加载失败'),
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
    String? error;

    final saved = await FxDialog.show<bool>(
      context: context,
      title: existing == null ? '新建观察标签' : '编辑观察标签',
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
              onTap: saving ? null : onTap,
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
              borderRadius: 999,
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
                    placeholder: '例如：分心、心流、精力低谷',
                  ),
                  const SizedBox(height: 14),
                  _dialogLabel(dialogContext, '归属维度'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      selectableChip(
                        label: '未归类 · 仅分析',
                        selected: dimensionKey == null || dimensionKey!.isEmpty,
                        onTap: () => setDialogState(() => dimensionKey = null),
                      ),
                      ...DimensionCatalog.all.map(
                        (item) => selectableChip(
                          label: '${item.icon} ${item.name}',
                          selected: dimensionKey == item.keyValue,
                          onTap:
                              () => setDialogState(
                                () => dimensionKey = item.keyValue,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _dialogLabel(dialogContext, '图标'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _presetEmojis
                        .map(
                          (item) => selectableChip(
                            label: item,
                            selected: item == icon,
                            onTap: () => setDialogState(() => icon = item),
                          ),
                        )
                        .toList(growable: false),
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
                                saving
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
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
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
                            saving
                                ? null
                                : () async {
                                  final name = nameController.text.trim();
                                  if (name.isEmpty) {
                                    setDialogState(() => error = '标签名称不能为空');
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
                                    setDialogState(() {
                                      saving = false;
                                      error = e.toString();
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
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '删除观察标签',
      content: '确定删除「${tag.name}」吗？已有行为事实仍会保留，但后续不会再用这个标签分类。',
      confirmText: '删除',
      destructive: true,
    );
    if (confirmed != true) return;
    try {
      await _repository.delete(tag);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }
}

class _ObservationTagGroup {
  final String label;
  final List<ObservationTag> tags;

  const _ObservationTagGroup({required this.label, required this.tags});
}
