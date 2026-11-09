import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../layout_tokens.dart';
import '../typography_tokens.dart';
import 'fx_button.dart';
import 'fx_icon_button.dart';

/// Slowlight 二级页面统一页头：返回 + 标题 + 右侧动作。
///
/// Android 使用 Page Title 可读层级；桌面端保持既有高保真二级页头密度。
/// 单一图标始终同标题行；短文字按钮空间足够时同排，宽操作在空间不足时下移。
class FxPageHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final IconData? actionIcon;
  final String? actionTooltip;
  final VoidCallback? onAction;
  /// Match the approved Android settings detail header, without altering
  /// other page headers or desktop alignment.
  final bool centerTitle;

  const FxPageHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.actionIcon,
    this.actionTooltip,
    this.onAction,
    this.centerTitle = false,
  });

  List<Widget> _actions(BuildContext context) {
    return [
      if (trailing != null) trailing!,
      if (actionIcon != null)
        FxIconButton(
          icon: actionIcon!,
          tooltip: actionTooltip ?? title,
          onPressed: onAction,
        ),
    ];
  }

  Widget _actionGroup(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: _actions(context),
    );
  }

  // Only estimate the one supported single-button action. Other composite
  // trailing widgets keep the conservative wrapping contract.
  bool _singleButtonFits(BuildContext context, double width) {
    final widget = trailing;
    if (widget is! FxButton || actionIcon != null) return false;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final titleText = TextPainter(
      text: TextSpan(
        text: title,
        style: SlowlightTypography.componentPageTitle(context),
      ),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final actionText = TextPainter(
      text: TextSpan(
        text: widget.label,
        style: SlowlightTypography.componentButton(
          context,
          compact: widget.size == FxButtonSize.sm,
        ),
      ),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();

    final iconSpace = widget.icon != null || widget.leading != null
        ? (widget.size == FxButtonSize.sm
            ? SlowlightIconSize.compactAction + 6
            : SlowlightIconSize.sm + SlowlightSpacing.md)
        : 0.0;
    final actionPadding = widget.size == FxButtonSize.sm ? 28.0 : 36.0;
    final needed = SlowlightPlatformDensity.iconButtonVisualSize +
        4 + 8 + titleText.width + actionText.width +
        iconSpace + actionPadding + 12;
    titleText.dispose();
    actionText.dispose();
    return needed <= width;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final back = onBack ?? () => Navigator.of(context).maybePop();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final largeText = scale >= 1.5;
    final hasActions = trailing != null || actionIcon != null;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      // Windows 高保真页头使用 16px 水平留白；Android 的字号与触控目标
      // 由 Theme / FxIconButton 自己处理，不反向撑大桌面页头。
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A single icon fits beside the back arrow and even a scaled title
          // at normal phone widths. Do not treat it like a wide form action:
          // the old 520dp threshold created an unnecessary second toolbar row.
          final singleIconAction =
              (trailing is FxIconButton && actionIcon == null) ||
              (trailing == null && actionIcon != null);
          final singleButtonFits =
              !singleIconAction && scale < 1.6 &&
              _singleButtonFits(context, constraints.maxWidth);
          final stackActions = hasActions &&
              (constraints.maxWidth < 180 ||
                  (!singleIconAction &&
                      !singleButtonFits &&
                      (constraints.maxWidth < 520 || scale >= 1.6)));
          final titleRow = Row(
            crossAxisAlignment:
                largeText ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              FxIconButton(
                icon: LucideIcons.chevronLeft,
                tooltip: '返回',
                onPressed: back,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: largeText ? 6 : 0),
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
                const SizedBox(width: 8),
                _actionGroup(context),
              ],
            ],
          );

          if (centerTitle && !hasActions && !largeText) {
            return SizedBox(
              width: double.infinity,
              height: SlowlightControlSize.minTouchTarget,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FxIconButton(
                      icon: LucideIcons.chevronLeft,
                      tooltip: '返回',
                      onPressed: back,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SlowlightControlSize.minTouchTarget + 4,
                    ),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: SlowlightTypography.componentPageTitle(context)
                          .copyWith(color: theme.colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
            );
          }
          if (!stackActions) return titleRow;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleRow,
              const SizedBox(height: 4),
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
