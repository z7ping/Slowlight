import '../ui/widgets/fx_cursor.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../models/tag.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../ui/widgets/fx_input.dart';
import '../ui/widgets/fx_dialog.dart';
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

  // 预设颜色数组
  static const List<String> presetColors = [
    '#0075de', // 蓝
    '#52c41a', // 绿
    '#fa8c16', // 橙
    '#ff4d4f', // 红
    '#722ed1', // 紫
    '#13c2c2', // 青
    '#eb2f96', // 粉
    '#8c8c8c', // 灰
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
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('加载标签失败'), backgroundColor: AppTheme.priorityHigh),
        );
      }
    }
  }

  void _toggleTag(Tag tag) {
    final selected = List<Tag>.from(widget.selectedTags);
    final index = selected.indexWhere((t) => t.id == tag.id);

    if (index >= 0) {
      selected.removeAt(index);
    } else {
      selected.add(tag);
    }

    widget.onChanged(selected);
  }

  void _showCreateTagDialog() {
    final nameController = TextEditingController();
    String selectedColor = presetColors[0];

    showShadDialog(
      context: context,
      barrierColor: FxDialog.barrierColor,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ShadDialog(
          title: const Text('新建标签'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FxInput(
                controller: nameController,
                label: '标签名称',
                placeholder: '输入标签名称...',
                autofocus: true,
              ),
              SizedBox(height: 16),
              Text(
                '选择颜色',
                style: TextStyle(
                    fontSize: AppTheme.textMd,
                    height: 1.5,
                    color: AppTheme.warmGray500),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: presetColors.map<Widget>((color) {
                  final isSelected = color == selectedColor;
                  return FxGestureDetector(
                    onTap: () => setDialogState(() => selectedColor = color),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: ColorUtils.safeParse(color),
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected
                            ? Border.all(color: AppTheme.white, width: 2)
                            : null,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: ColorUtils.safeParse(color)
                                      .withValues(alpha: 0.5),
                                  blurRadius: 4,
                                )
                              ]
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ShadButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                try {
                  final tag = await ApiService.createTag(
                    name: name,
                    color: selectedColor,
                  );

                  setState(() => _allTags.add(tag));

                  // 自动选中新创建的标签
                  final selected = List<Tag>.from(widget.selectedTags);
                  selected.add(tag);
                  widget.onChanged(selected);

                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('创建标签失败'),
                        backgroundColor: AppTheme.priorityHigh,
                      ),
                    );
                  }
                }
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return SizedBox(
        height: 40,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // 已有标签
        ..._allTags.map((tag) {
          final isSelected = widget.selectedTags.any((t) => t.id == tag.id);
          final color = ColorUtils.safeParse(tag.color);

          return FilterChip(
            label: Text(tag.name),
            labelStyle: TextStyle(
              color: isSelected ? AppTheme.white : AppTheme.warmGray500,
              fontSize: AppTheme.textMd,
              fontWeight: FontWeight.w500,
            ),
            selected: isSelected,
            selectedColor: color,
            backgroundColor: color.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: isSelected ? color : color.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            checkmarkColor: AppTheme.white,
            onSelected: (_) => _toggleTag(tag),
          );
        }),

        // 新建标签按钮
        ActionChip(
          avatar: Icon(Icons.add, size: 16, color: AppTheme.warmGray500),
          label: Text(
            '新建',
            style: TextStyle(
              fontSize: AppTheme.textMd,
              height: 1.5,
              color: AppTheme.warmGray500,
            ),
          ),
          backgroundColor: AppTheme.warmWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: AppTheme.warmBorder, width: 1),
          ),
          onPressed: _showCreateTagDialog,
        ),
      ],
    );
  }
}
