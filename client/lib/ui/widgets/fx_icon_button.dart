import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../layout_tokens.dart';
import 'fx_tooltip.dart';

enum FxIconButtonVariant { ghost, outline }

/// FxIconButton — 统一图标按钮。
///
/// 业务页面不直接依赖 Material IconButton；视觉由 shadcn_ui 的专用
/// ShadIconButton 承载，避免把普通文字按钮的水平内边距硬塞进正方形尺寸。
/// Slowlight 统一使用最小触控目标 Token。
class FxIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double iconSize;
  final Color? foregroundColor;
  final FxIconButtonVariant variant;

  const FxIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.iconSize = SlowlightIconSize.md,
    this.foregroundColor,
    this.variant = FxIconButtonVariant.ghost,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: iconSize, color: foregroundColor);
    final Widget button = switch (variant) {
      FxIconButtonVariant.ghost => ShadIconButton.ghost(
          width: SlowlightControlSize.minTouchTarget,
          height: SlowlightControlSize.minTouchTarget,
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          iconSize: iconSize,
          icon: iconWidget,
        ),
      FxIconButtonVariant.outline => ShadIconButton.outline(
          width: SlowlightControlSize.minTouchTarget,
          height: SlowlightControlSize.minTouchTarget,
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          iconSize: iconSize,
          icon: iconWidget,
        ),
    };

    if (tooltip != null && tooltip!.isNotEmpty) {
      return FxTooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
