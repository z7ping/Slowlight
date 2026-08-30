import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app_theme.dart';
import '../typography_tokens.dart';
import 'fx_icon_button.dart';

/// Slowlight 二级页面统一页头：返回 + 标题 + 右侧动作。
///
/// 页面标题统一使用 Page Title 语义；图标动作通过 FxIconButton 承载，
/// 避免业务页头直接依赖 Material 视觉按钮。
class FxPageHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final IconData? actionIcon;
  final String? actionTooltip;
  final VoidCallback? onAction;

  const FxPageHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.actionIcon,
    this.actionTooltip,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final back = onBack ?? () => Navigator.of(context).maybePop();
    final largeText = MediaQuery.textScalerOf(context)
            .scale(SlowlightTypography.pageTitleSize) >=
        SlowlightTypography.pageTitleSize * 1.5;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spaceSm,
        vertical: AppTheme.spaceXs,
      ),
      child: Row(
        crossAxisAlignment:
            largeText ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          FxIconButton(
            icon: LucideIcons.chevronLeft,
            tooltip: '返回',
            onPressed: back,
          ),
          const SizedBox(width: AppTheme.spaceXs),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: largeText ? 6 : 0),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SlowlightTypography.pageTitle(context).copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppTheme.spaceSm),
            trailing!,
          ],
          if (actionIcon != null && onAction != null) ...[
            const SizedBox(width: AppTheme.spaceXs),
            FxIconButton(
              icon: actionIcon!,
              tooltip: actionTooltip ?? title,
              onPressed: onAction!,
            ),
          ],
        ],
      ),
    );
  }
}
