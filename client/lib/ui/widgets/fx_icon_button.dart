import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'fx_tooltip.dart';

enum FxIconButtonVariant { ghost, outline }

/// FxIconButton — 统一图标按钮。
///
/// 业务页面不直接依赖 Material IconButton；视觉由 shadcn_ui 的专用
/// ShadIconButton 承载，避免把普通文字按钮的水平内边距硬塞进正方形尺寸。
/// Slowlight 统一使用 44px 最小触控目标。
class FxIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double iconSize;
  final FxIconButtonVariant variant;

  const FxIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.iconSize = 18,
    this.variant = FxIconButtonVariant.ghost,
  });

  @override
  Widget build(BuildContext context) {
    final Widget button = switch (variant) {
      FxIconButtonVariant.ghost => ShadIconButton.ghost(
          width: 44,
          height: 44,
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          iconSize: iconSize,
          icon: Icon(icon, size: iconSize),
        ),
      FxIconButtonVariant.outline => ShadIconButton.outline(
          width: 44,
          height: 44,
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          iconSize: iconSize,
          icon: Icon(icon, size: iconSize),
        ),
    };

    if (tooltip != null && tooltip!.isNotEmpty) {
      return FxTooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
