import 'package:flutter/material.dart';

import '../models/tag.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../utils/color_utils.dart';

class TagPicker extends StatefulWidget {
  final List<Tag> selectedTags;
  final ValueChanged<List<Tag>> onChanged;

  const TagPicker({
    super.key,
    required this.selectedTags,
    required this.onChanged,
  });

  @override
  State<TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<TagPicker> {
  List<Tag> _allTags = [];
  bool _isLoading = true;

  static const List<String> presetColors = [
    '#0075de',
    '#52c41a',
    '#fa8c16',
    '#ff4d4f',
    '#722ed1',
    '#13c2c2',
    '#eb2f96',
    '#8c8c8c',
  ];

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    try {
      final tags = await ApiService.getTags();
      if (mounted) {
        setState(() {
          _allTags = tags;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        FxNotice.showContent(context, Text('加载标签失败'));
      }
    }
  }

  void _toggleTag(Tag tag) {
    final selected = List<Tag>.from(widget.selectedTags);
    final index = selected.indexWhere((item) => item.id == tag.id);
    if (index >= 0) {
      selected.removeAt(index);
    } else {
      selected.add(tag);
    }
    widget.onChanged(selected);
  }

  Future<void> _showCreateTagDialog() async {
    final nameController = TextEditingController();
    var selectedColor = presetColors.first;

    await FxDialog.show<void>(
      context: context,
      title: '新建标签',
      width: 460,
      child: StatefulBuilder(
        builder:
            (dialogContext, setDialogState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FxInput(
                  controller: nameController,
                  label: '标签名称',
                  placeholder: '输入标签名称…',
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                Text(
                  '选择颜色',
                  style: SlowlightTypography.secondary(dialogContext).copyWith(
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: presetColors
                      .map((value) {
                        final color = ColorUtils.safeParse(value);
                        final selected = value == selectedColor;
                        return FxInkWell(
                          onTap:
                              () => setDialogState(() => selectedColor = value),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
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
                                            ? Theme.of(
                                              dialogContext,
                                            ).colorScheme.onSurface
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
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FxButton(
                      label: '取消',
                      variant: FxButtonVariant.outline,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                    FxButton(
                      label: '创建',
                      onPressed: () async {
                        final name = nameController.text.trim();
                        if (name.isEmpty) return;
                        try {
                          final tag = await ApiService.createTag(
                            name: name,
                            color: selectedColor,
                          );
                          if (!mounted) return;
                          setState(() => _allTags.add(tag));
                          widget.onChanged([...widget.selectedTags, tag]);
                          if (dialogContext.mounted)
                            Navigator.of(dialogContext).pop();
                        } catch (_) {
                          if (dialogContext.mounted) {
                            FxNotice.showContent(dialogContext, Text('创建标签失败'));
                          }
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
      ),
    );
    nameController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 40,
        child: Center(child: FxCircularProgress()),
      );
    }

    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ..._allTags.map((tag) {
          final selected = widget.selectedTags.any((item) => item.id == tag.id);
          final color = ColorUtils.safeParse(tag.color);
          return FxInkWell(
            onTap: () => _toggleTag(tag),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: FxChip(
              label: tag.name,
              backgroundColor: selected ? color : color.withValues(alpha: .10),
              foregroundColor:
                  selected ? Colors.white : theme.colorScheme.onSurfaceVariant,
              borderColor: selected ? color : color.withValues(alpha: .32),
              borderRadius: AppTheme.radiusMd,
            ),
          );
        }),
        FxButton(
          label: '新建',
          icon: Icons.add,
          variant: FxButtonVariant.outline,
          size: FxButtonSize.sm,
          onPressed: _showCreateTagDialog,
        ),
      ],
    );
  }
}
