import 'package:flutter/material.dart';

import '../models/observation_tag.dart';
import '../ui/fx.dart';

/// 统一的标签选择视觉层。暂时复用现有观察标签数据源；
/// 关联模型的多标签迁移不属于本轮界面改动。
class TagChoiceField extends StatelessWidget {
  final List<ObservationTag> tags;
  final int? selectedTagId;
  final ValueChanged<int?> onChanged;
  final bool enabled;
  final String label;

  const TagChoiceField({
    super.key,
    required this.tags,
    required this.selectedTagId,
    required this.onChanged,
    this.enabled = true,
    this.label = '标签（可选）',
  });

  @override
  Widget build(BuildContext context) {
    return FxFormField(
      label: label,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          FxChoiceChip(
            label: '无标签',
            selected: selectedTagId == null,
            onTap: enabled ? () => onChanged(null) : null,
          ),
          ...tags.map((tag) => FxChoiceChip(
                label: '#${tag.name}',
                selected: selectedTagId == tag.id,
                onTap: enabled ? () => onChanged(tag.id) : null,
              )),
        ],
      ),
    );
  }
}
