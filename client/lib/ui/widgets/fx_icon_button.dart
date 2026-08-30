import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'fx_tooltip.dart';

/// FxIconButton — 统一图标按钮。
///
/// 业务页面不直接依赖 Material IconButton；视觉由 shadcn_ui 承载，
/// Slowlight 统一使用 44px 最小触控目标。
class FxIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double iconSize;

  const FxIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    Widget button = SizedBox(
      width: 44,
      height: 44,
      child: ShadButton.ghost(
        onPressed: onPressed,
        size: ShadButtonSize.regular,
        child: Icon(icon, size: iconSize),
      ),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      button = FxTooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
