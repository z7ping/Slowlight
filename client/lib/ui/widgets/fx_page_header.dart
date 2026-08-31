import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../layout_tokens.dart';
import '../typography_tokens.dart';
import 'fx_icon_button.dart';

/// Slowlight 二级页面统一页头：返回 + 标题 + 右侧动作。
///
/// Android 使用 Page Title 可读层级；桌面端保持既有高保真二级页头密度。
/// 动作在宽布局固定锚定页头右侧，窄屏或超大字体时动作整体落到下一行。
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

  List<Widget> _actions(BuildContext context) {
    return [
      if (trailing != null) trailing!,
      if (actionIcon != null && onAction != null)
        FxIconButton(
          icon: actionIcon!,
          tooltip: actionTooltip ?? title,
          onPressed: onAction!,
        ),
    ];
  }

  Widget _actionGroup(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: SlowlightSpacing.xs,
      runSpacing: SlowlightSpacing.xs,
      children: _actions(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final back = onBack ?? () => Navigator.of(context).maybePop();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final largeText = scale >= 1.5;
    final hasActions = trailing != null || (actionIcon != null && onAction != null);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: SlowlightSpacing.md,
        vertical: SlowlightSpacing.xs,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackActions =
              hasActions && (constraints.maxWidth < 520 || scale >= 1.6);
          final titleRow = Row(
            crossAxisAlignment:
                largeText ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              FxIconButton(
                icon: LucideIcons.chevronLeft,
                tooltip: '返回',
                onPressed: back,
              ),
              const SizedBox(width: SlowlightSpacing.xs),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: largeText ? SlowlightSpacing.sm : 0,
                  ),
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SlowlightTypography.componentPageTitle(
                      context,
                    ).copyWith(color: theme.colorScheme.onSurface),
                  ),
                ),
              ),
              if (hasActions && !stackActions) ...[
                const SizedBox(width: SlowlightSpacing.md),
                _actionGroup(context),
              ],
            ],
          );

          if (!stackActions) return titleRow;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleRow,
              const SizedBox(height: SlowlightSpacing.xs),
              Align(
                alignment: Alignment.centerRight,
                child: _actionGroup(context),
              ),
            ],
          );
        },
      ),
    );
  }
}
