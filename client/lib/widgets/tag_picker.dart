import 'package:flutter/material.dart';

import '../models/tag.dart';
import '../models/observation_tag.dart';
import 'tag_choice_field.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../utils/color_utils.dart';

class TagPicker extends StatefulWidget {
  final List<Tag> selectedTags;
  final ValueChanged<List<Tag>> onChanged;
  final bool enabled;
  final String label;
  final bool allowCreation;
  final bool showEmptyOption;
  /// In task popovers, create new tags in place instead of opening a dialog.
  final bool inlineCreation;

  const TagPicker({
    super.key,
    required this.selectedTags,
    required this.onChanged,
    this.enabled = true,
    this.label = '标签（可多选）',
    this.allowCreation = true,
    this.showEmptyOption = true,
    this.inlineCreation = false,
  });

  @override
  State<TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<TagPicker> {
  List<Tag> _allTags = [];
  bool _isLoading = true;
  bool _inlineCreating = false;
  bool _creatingTag = false;
  String _inlineTagColor = presetColors.first;
  final TextEditingController _inlineTagName = TextEditingController();

  @override
  void dispose() {
    _inlineTagName.dispose();
    super.dispose();
  }

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

  Future<void> _createInlineTag() async {
    final name = _inlineTagName.text.trim();
    if (name.isEmpty || _creatingTag) return;
    setState(() => _creatingTag = true);
    try {
      final tag = await ApiService.createTag(
        name: name,
        color: _inlineTagColor,
      );
      if (!mounted) return;
      setState(() {
        _allTags = [..._allTags, tag];
        _inlineCreating = false;
        _inlineTagName.clear();
      });
      widget.onChanged([...widget.selectedTags, tag]);
    } catch (_) {
      if (mounted) FxNotice.showContent(context, const Text('创建标签失败，请重试'));
    } finally {
      if (mounted) setState(() => _creatingTag = false);
    }
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
                            SlowlightRadius.md,
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TagChoiceField(
      tags: {for (final tag in [...widget.selectedTags, ..._allTags]) tag.id: tag}.values
          .map((tag) => ObservationTag(
                id: tag.id,
                name: tag.name,
                icon: '🏷️',
                color: tag.color,
              ))
          .toList(growable: false),
      selectedTagIds: widget.selectedTags.map((tag) => tag.id).toSet(),
      onMultipleChanged: (ids) {
        final byId = {for (final tag in [...widget.selectedTags, ..._allTags]) tag.id: tag};
        widget.onChanged([
          for (final id in ids)
            if (byId.containsKey(id)) byId[id]!,
        ]);
      },
      enabled: widget.enabled,
      onCreateTag: widget.enabled && widget.allowCreation
          ? widget.inlineCreation
              ? () => setState(() => _inlineCreating = true)
              : _showCreateTagDialog
          : null,
      showEmptyOption: widget.showEmptyOption,
      label: widget.label,
        ),
        if (_inlineCreating) ...[
          const SizedBox(height: SlowlightSpacing.md),
          FxInput(
            key: const ValueKey('task.detail.inlineTagName'),
            controller: _inlineTagName,
            enabled: !_creatingTag,
            autofocus: true,
            placeholder: '新标签名称',
          ),
          const SizedBox(height: SlowlightSpacing.md),
          Wrap(
            spacing: SlowlightSpacing.xs,
            runSpacing: SlowlightSpacing.xs,
            children: [
              for (final color in presetColors)
                FxInkWell(
                  onTap: _creatingTag
                      ? null
                      : () => setState(() => _inlineTagColor = color),
                  borderRadius: BorderRadius.circular(SlowlightRadius.md),
                  child: SizedBox(
                    width: SlowlightControlSize.minTouchTarget,
                    height: SlowlightControlSize.minTouchTarget,
                    child: Center(
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: ColorUtils.safeParse(color),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _inlineTagColor == color
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: SlowlightSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FxButton(
                label: '取消',
                variant: FxButtonVariant.ghost,
                size: FxButtonSize.sm,
                onPressed: _creatingTag ? null : () => setState(() {
                  _inlineCreating = false;
                  _inlineTagName.clear();
                }),
              ),
              const SizedBox(width: SlowlightSpacing.xs),
              FxButton(
                label: _creatingTag ? '添加中…' : '添加',
                size: FxButtonSize.sm,
                onPressed: _creatingTag ? null : _createInlineTag,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
