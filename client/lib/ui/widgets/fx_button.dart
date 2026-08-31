import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../layout_tokens.dart';
import '../typography_tokens.dart';

/// FxButton — 按钮组件。
///
/// Fx 统一按钮语义、尺寸、交互和触摸区域；视觉仍以 ShadButton 为底座。
/// 文字尺度由 SlowlightTypography 的平台语义统一解析，避免 Fx 化把 Windows
/// 既有高密度按钮误放大为 Android 尺度。
enum FxButtonVariant { primary, secondary, outline, ghost, destructive, link }

enum FxButtonSize { sm, md, lg }

class FxButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final FxButtonVariant variant;
  final FxButtonSize size;
  final IconData? icon;
  final bool expanded;
  final Color? foregroundColor;

  const FxButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = FxButtonVariant.primary,
    this.size = FxButtonSize.md,
    this.icon,
    this.expanded = false,
    this.foregroundColor,
  });

  bool get _isCompactAction => size == FxButtonSize.sm;

  Widget _buildChild(BuildContext context) {
    final textStyle = SlowlightTypography.componentButton(
      context,
      compact: _isCompactAction,
    ).copyWith(color: foregroundColor);
    final text = Text(label, style: textStyle);
    if (icon != null) {
      return Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: _isCompactAction
                ? SlowlightIconSize.compactAction
                : SlowlightIconSize.sm,
            color: foregroundColor,
          ),
          SizedBox(
            width: _isCompactAction
                ? SlowlightSpacing.sm
                : SlowlightSpacing.md,
          ),
          text,
        ],
      );
    }
    return text;
  }

  ShadButtonSize get _shadSize {
    switch (size) {
      case FxButtonSize.sm:
        return ShadButtonSize.sm;
      case FxButtonSize.lg:
        return ShadButtonSize.lg;
      case FxButtonSize.md:
        return ShadButtonSize.regular;
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _buildChild(context);
    final Widget button;
    switch (variant) {
      case FxButtonVariant.primary:
        button = ShadButton(
          onPressed: onPressed,
          size: _shadSize,
          child: child,
        );
        break;
      case FxButtonVariant.secondary:
        button = ShadButton.secondary(
          onPressed: onPressed,
          size: _shadSize,
          child: child,
        );
        break;
      case FxButtonVariant.outline:
        button = ShadButton.outline(
          onPressed: onPressed,
          size: _shadSize,
          child: child,
        );
        break;
      case FxButtonVariant.ghost:
        button = ShadButton.ghost(
          onPressed: onPressed,
          size: _shadSize,
          child: child,
        );
        break;
      case FxButtonVariant.destructive:
        button = ShadButton.destructive(
          onPressed: onPressed,
          size: _shadSize,
          child: child,
        );
        break;
      case FxButtonVariant.link:
        button = ShadButton.link(
          onPressed: onPressed,
          size: _shadSize,
          child: child,
        );
        break;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return button;
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: SlowlightControlSize.minTouchTarget,
      ),
      child: button,
    );
  }
}
