import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../typography_tokens.dart';

/// FxCheckbox — 统一复选框组件。
///
/// Android 使用可读字号；桌面端继承 ShadCheckbox 既有标签视觉。
class FxCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final bool enabled;

  const FxCheckbox({
    super.key,
    required this.value,
    this.onChanged,
    this.label,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ShadCheckbox(
      value: value,
      onChanged: enabled ? onChanged : null,
      label: label == null
          ? null
          : Text(
              label!,
              style: SlowlightTypography.useAndroidComponentTypography
                  ? SlowlightTypography.secondary(context)
                  : null,
            ),
    );
  }
}
