import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';
import 'high_fidelity_ui.dart';

/// 高保真原型 L2 推送页统一页头：返回 + 标题 + 右侧动作。
class HfPageHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final IconData? actionIcon;
  final String? actionTooltip;
  final VoidCallback? onAction;

  const HfPageHeader({
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
    return Container(
      decoration: BoxDecoration(
        color: hfSurface(context),
        border: Border(bottom: BorderSide(color: hfDivider(context))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceSm, vertical: AppTheme.spaceXs),
      child: Row(
        children: [
          _HeaderIconButton(
            icon: LucideIcons.chevronLeft,
            tooltip: '返回',
            onPressed: back,
          ),
          const SizedBox(width: AppTheme.spaceXs),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
          if (actionIcon != null && onAction != null) ...[
            if (trailing != null) const SizedBox(width: AppTheme.spaceXs),
            _HeaderIconButton(
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

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
        ),
      ),
    );
  }
}
