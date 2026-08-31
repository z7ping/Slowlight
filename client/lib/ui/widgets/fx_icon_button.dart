import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../layout_tokens.dart';
import 'fx_tooltip.dart';

enum FxIconButtonVariant { ghost, outline }

/// FxIconButton — 统一图标按钮。
///
/// 业务页面不直接依赖 Material IconButton；视觉由 shadcn_ui 的专用
/// ShadIconButton 承载。Windows 保持高保真中的 30px 紧凑可见尺寸，
/// Android 才使用 44px 最低触控目标，避免移动端触控规则撑大桌面 Header、
/// Row 与 hover 背景。
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
    final android =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final visualSize = android ? SlowlightControlSize.minTouchTarget : 30.0;
    final iconWidget = Icon(icon, size: iconSize, color: foregroundColor);
    final Widget button = switch (variant) {
      FxIconButtonVariant.ghost => ShadIconButton.ghost(
          width: visualSize,
          height: visualSize,
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          iconSize: iconSize,
          icon: iconWidget,
        ),
      FxIconButtonVariant.outline => ShadIconButton.outline(
          width: visualSize,
          height: visualSize,
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
