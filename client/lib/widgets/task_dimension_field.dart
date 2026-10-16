import 'package:flutter/material.dart';

import '../models/dimension.dart';
import '../ui/fx.dart';
import '../utils/color_utils.dart';

/// 快捷记录与完整表单共用四维选择；选项视觉由 FxChoiceChip 提供。
class TaskDimensionField extends StatelessWidget {
  final String? selectedKey;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  const TaskDimensionField({
    super.key,
    required this.selectedKey,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return FxFormField(
      label: '归属维度（可选）',
      child: Wrap(
        spacing: SlowlightSpacing.md,
        runSpacing: SlowlightSpacing.md,
        children: [
          FxChoiceChip(
            label: '未归类',
            selected: selectedKey == null,
            onTap: enabled ? () => onChanged(null) : null,
          ),
          ...DimensionCatalog.all.map(
            (dimension) => FxChoiceChip(
              label: '${dimension.icon} ${dimension.name}',
              selected: selectedKey == dimension.keyValue,
              selectionColor: ColorUtils.safeParse(dimension.color),
              onTap: enabled
                  ? () => onChanged(dimension.keyValue)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
