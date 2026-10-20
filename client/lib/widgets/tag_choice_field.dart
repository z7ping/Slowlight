import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/observation_tag.dart';
import '../utils/color_utils.dart';
import '../ui/fx.dart';

/// 统一标签选择视觉层：兼容旧单选，并为多标签调用方提供多选交互。
/// 多选仅返回选中 ID 集合，持久化由业务调用方负责。
class TagChoiceField extends StatelessWidget {
  final List<ObservationTag> tags;
  final int? selectedTagId;
  final ValueChanged<int?>? onChanged;
  final Set<int>? selectedTagIds;
  final ValueChanged<Set<int>>? onMultipleChanged;
  final bool enabled;
  final VoidCallback? onCreateTag;
  final String label;

  const TagChoiceField({
    super.key,
    required this.tags,
    this.selectedTagId,
    this.onChanged,
    this.selectedTagIds,
    this.onMultipleChanged,
    this.enabled = true,
    this.onCreateTag,
    this.label = '标签（可选）',
  });

  @override
  Widget build(BuildContext context) {
    final multiple = onMultipleChanged != null;
    final selectedIds = selectedTagIds ?? <int>{};
    return FxFormField(
      label: label,
      child: Wrap(
        spacing: SlowlightSpacing.md,
        runSpacing: SlowlightSpacing.md,
        children: [
          FxChoiceChip(
            label: '无标签',
            selected: multiple ? selectedIds.isEmpty : selectedTagId == null,
            // “无标签”是默认状态，不使用强调色冒充用户主动选择的标签。
            selectionColor: Theme.of(context).colorScheme.onSurfaceVariant,
            onTap: enabled
                ? () => multiple ? onMultipleChanged!(<int>{}) : onChanged?.call(null)
                : null,
          ),
          ...tags.map((tag) => FxChoiceChip(
                label: '#${tag.name}',
                selected: multiple ? selectedIds.contains(tag.id) : selectedTagId == tag.id,
                selectionColor: ColorUtils.safeParse(tag.color),
                onTap: enabled
                    ? () {
                        if (!multiple) {
                          onChanged?.call(tag.id);
                          return;
                        }
                        final updated = {...selectedIds};
                        if (!updated.add(tag.id)) updated.remove(tag.id);
                        onMultipleChanged!(updated);
                      }
                    : null,
              )),
          if (onCreateTag != null)
            FxChoiceChip(
              label: '新建',
              icon: LucideIcons.plus,
              selected: false,
              onTap: enabled ? onCreateTag : null,
            ),
        ],
      ),
    );
  }
}
