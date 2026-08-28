import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/dimension.dart';
import '../models/observation_tag.dart';
import '../repositories/observation_tag_repository.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../utils/color_utils.dart';
import '../widgets/high_fidelity/high_fidelity_ui.dart';

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
      groups.add(
        _ObservationTagGroup(
          label: '未归类 · 仅分析',
          tags: unclassified,
        ),
      );
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _errorView();

    final theme = Theme.of(context);
    final groups = _groups();
    return RefreshIndicator(
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      HfChip('${_tags.length} 个标签'),
                      const Spacer(),
                      const SizedBox(width: 16),
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
                    HfEmptyState(
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
    return HfCard(
      padding: const EdgeInsets.all(14),
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '标签和维度是两回事',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            '身体、认知、产出、关系是固定长期坐标；标签是你自己的分类方式。标签可以归属某个维度，也可以保持“未归类 · 仅分析”。',
            style: TextStyle(
              fontSize: AppTheme.textSm,
              height: 1.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: DimensionCatalog.all
                .map((item) => HfChip('${item.icon} ${item.name}'))
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
            style: TextStyle(
              fontSize: AppTheme.textXs,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        HfCard(
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
        border: Border(bottom: BorderSide(color: hfDivider(context))),
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
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    '#${tag.name}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (tag.isDefault) ...[
                  const SizedBox(width: 6),
                  const HfChip('默认'),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              tooltip: '编辑',
              onPressed: () => _editTag(tag),
              icon: const Icon(LucideIcons.pencil, size: 17),
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              tooltip: tag.isDefault ? '默认标签不可删除' : '删除',
              onPressed: tag.isDefault ? null : () => _confirmDelete(tag),
              icon: Icon(
                LucideIcons.trash2,
                size: 17,
                color: tag.isDefault
                    ? theme.colorScheme.onSurfaceVariant.withValues(alpha: .35)
                    : theme.colorScheme.error,
              ),
            ),
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
          Icon(LucideIcons.circleAlert,
              size: 32, color: theme.colorScheme.error),
          const SizedBox(height: 10),
          const Text('观察标签加载失败'),
          const SizedBox(height: 6),
          Text(
            _error!,
            style: TextStyle(
              fontSize: AppTheme.textXs,
              color: theme.colorScheme.onSurfaceVariant,
            ),
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

    final saved = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .45),
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final theme = Theme.of(dialogContext);
          return Dialog(
            backgroundColor: hfSurface(dialogContext),
            surfaceTintColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              side: BorderSide(color: hfBorder(dialogContext)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540, maxHeight: 700),
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
                            existing == null ? '新建观察标签' : '编辑观察标签',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: IconButton(
                            tooltip: '关闭',
                            onPressed: saving
                                ? null
                                : () => Navigator.pop(dialogContext, false),
                            icon: const Icon(LucideIcons.x, size: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      enabled: !saving,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: '例如：分心、心流、精力低谷',
                      ),
                    ),
                    const SizedBox(height: 14),
                    _dialogLabel(dialogContext, '归属维度'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          label: const Text('未归类 · 仅分析'),
                          labelStyle:
                              const TextStyle(fontSize: AppTheme.textXs),
                          showCheckmark: false,
                          selected:
                              dimensionKey == null || dimensionKey!.isEmpty,
                          selectedColor:
                              activePalette.accent.withValues(alpha: .12),
                          onSelected: (_) =>
                              setDialogState(() => dimensionKey = null),
                        ),
                        ...DimensionCatalog.all.map((item) {
                          final selected = dimensionKey == item.keyValue;
                          return ChoiceChip(
                            label: Text('${item.icon} ${item.name}'),
                            labelStyle:
                                const TextStyle(fontSize: AppTheme.textXs),
                            showCheckmark: false,
                            selected: selected,
                            selectedColor:
                                activePalette.accent.withValues(alpha: .12),
                            onSelected: (_) => setDialogState(
                              () => dimensionKey = item.keyValue,
                            ),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _dialogLabel(dialogContext, '图标'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _presetEmojis.map((item) {
                        final selected = item == icon;
                        return ChoiceChip(
                          label: Text(item),
                          showCheckmark: false,
                          selected: selected,
                          selectedColor:
                              activePalette.accent.withValues(alpha: .12),
                          onSelected: (_) => setDialogState(() => icon = item),
                        );
                      }).toList(growable: false),
                    ),
                    const SizedBox(height: 14),
                    _dialogLabel(dialogContext, '颜色'),
                    Wrap(
                      spacing: 8,
                      children: _presetColors.map((item) {
                        final selected =
                            item.toLowerCase() == color.toLowerCase();
                        return InkWell(
                          onTap: saving
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
                        style: TextStyle(
                          fontSize: AppTheme.textXs,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FxButton(
                          label: '取消',
                          variant: FxButtonVariant.outline,
                          onPressed: saving
                              ? null
                              : () => Navigator.pop(dialogContext, false),
                        ),
                        const SizedBox(width: 8),
                        FxButton(
                          label: saving ? '保存中…' : '保存',
                          onPressed: saving
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
                                      Navigator.pop(dialogContext, true);
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
          style: TextStyle(
            fontSize: AppTheme.textXs,
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
    );
    if (confirmed != true) return;
    try {
      await _repository.delete(tag);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
    }
  }
}

class _ObservationTagGroup {
  final String label;
  final List<ObservationTag> tags;

  const _ObservationTagGroup({required this.label, required this.tags});
}
