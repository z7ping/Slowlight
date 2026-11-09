import 'package:flutter/material.dart';

import '../layout_tokens.dart';
import '../typography_tokens.dart';

/// Slowlight 统一分区标题。
///
/// 分区标题属于卡片内部的高密度导航/说明层级，不与页面标题或卡片主标题抢层级。
/// Android 使用可读的辅助层级；桌面端保持既定高密度字号。
class FxSectionHeader extends StatelessWidget {
  final String title;
  final TextStyle? titleStyle;
  final String? trailing;
  final Widget? trailingWidget;

  const FxSectionHeader({
    super.key,
    required this.title,
    this.titleStyle,
    this.trailing,
    this.trailingWidget,
  });

  Widget _copy(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: titleStyle ?? SlowlightTypography.componentSecondary(context).copyWith(
              // Fx 化前正式分区标题组件使用 13px / 600；这里保持相同层级，
              // 不因为迁移到统一组件顺便把桌面分区标题加粗到 700。
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: SlowlightSpacing.md),
          Flexible(
            child: Text(
              trailing!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SlowlightTypography.caption(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final action = trailingWidget;
    if (action == null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: SlowlightControlSize.buttonSm,
        ),
        child: Align(alignment: Alignment.centerLeft, child: _copy(context)),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: SlowlightControlSize.buttonSm,
      ),
      // Measure actual title/action sizes instead of a 300/440dp threshold.
      child: OverflowBar(
        alignment: MainAxisAlignment.spaceBetween,
        overflowAlignment: OverflowBarAlignment.end,
        spacing: SlowlightSpacing.xl,
        overflowSpacing: SlowlightSpacing.xs,
        children: [_copy(context), action],
      ),
    );
  }
}
