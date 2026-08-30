import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../typography_tokens.dart';

/// FxSwitch — 统一开关组件。
///
/// label / description 统一由产品排版 Token 管理，业务页面不再通过
/// SwitchListTile 等 Material 视觉组件自行拼装。
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
    final labelWidget = label == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label!,
                style: SlowlightTypography.secondary(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
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
