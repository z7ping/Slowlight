import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../layout_tokens.dart';
import 'fx_tooltip.dart';

enum FxIconButtonVariant { ghost, outline }

/// FxIconButton — 统一图标按钮。
///
/// 业务页面不直接依赖 Material IconButton；视觉由 shadcn_ui 的专用
/// ShadIconButton 承载。可视尺寸由平台密度层统一解析，组件本身不判断平台。
class FxIconButton extends StatefulWidget {
  final IconData icon;
  final FutureOr<void> Function()? onPressed;
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
  State<FxIconButton> createState() => _FxIconButtonState();
}

class _FxIconButtonState extends State<FxIconButton> {
  bool _running = false;

  Future<void> _invoke() async {
    final action = widget.onPressed;
    if (_running || action == null) return;
    setState(() => _running = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  VoidCallback? get _effectiveAction =>
      widget.onPressed == null || _running ? null : _invoke;

  @override
  Widget build(BuildContext context) {
    final visualSize = SlowlightPlatformDensity.iconButtonVisualSize;
    final iconWidget = Icon(widget.icon, size: widget.iconSize, color: widget.foregroundColor);
    final Widget button = switch (widget.variant) {
      FxIconButtonVariant.ghost => ShadIconButton.ghost(
          width: visualSize,
          height: visualSize,
          padding: EdgeInsets.zero,
          onPressed: _effectiveAction,
          iconSize: widget.iconSize,
          icon: iconWidget,
        ),
      FxIconButtonVariant.outline => ShadIconButton.outline(
          width: visualSize,
          height: visualSize,
          padding: EdgeInsets.zero,
          onPressed: _effectiveAction,
          iconSize: widget.iconSize,
          icon: iconWidget,
        ),
    };

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      return FxTooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}
