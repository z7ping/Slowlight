import 'package:flutter/material.dart';

import '../typography_tokens.dart';

/// Slowlight 统一分区标题。
///
/// 分区标题属于卡片内部的高密度导航/说明层级，不与页面标题或卡片主标题抢层级。
class FxSectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget? trailingWidget;

  const FxSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.trailingWidget,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SlowlightTypography.secondary(context).copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                trailing!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SlowlightTypography.caption(context).copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          if (trailingWidget != null) ...[
            const Spacer(),
            trailingWidget!,
          ],
        ],
      ),
    );
  }
}
