import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../app_theme.dart';
import '../typography_tokens.dart';

/// FxSwitch — 统一开关组件。
///
/// Android 使用新的语义排版；桌面端保留迁移前开关标签的字号和正常字重。
class FxSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final String? description;

  const FxSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.label,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final useAndroidTypography =
        SlowlightTypography.useAndroidComponentTypography;
    final labelWidget = label == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label!,
                style: useAndroidTypography
                    ? SlowlightTypography.secondary(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600)
                    : const TextStyle(fontSize: AppTheme.textMd, height: 1.5),
              ),
              if (description != null && description!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  description!,
                  style: SlowlightTypography.caption(context).copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          );

    return ShadSwitch(
      value: value,
      onChanged: onChanged,
      label: labelWidget,
    );
  }
}
