import 'package:flutter/material.dart';

import '../typography_tokens.dart';

/// Slowlight 统一分区标题。
///
/// 用于卡片组、页面区块和带辅助信息/右侧动作的标题行。
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
              style: SlowlightTypography.cardTitle(context).copyWith(
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
                style: SlowlightTypography.secondary(context).copyWith(
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
