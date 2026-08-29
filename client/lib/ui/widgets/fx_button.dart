import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../typography_tokens.dart';

/// FxButton — 按钮组件
enum FxButtonVariant { primary, secondary, outline, ghost, destructive, link }

enum FxButtonSize { sm, md, lg }

class FxButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final FxButtonVariant variant;
  final FxButtonSize size;
  final IconData? icon;
  final bool expanded;

  const FxButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = FxButtonVariant.primary,
    this.size = FxButtonSize.md,
    this.icon,
    this.expanded = false,
  });

  Widget _buildChild() {
    final text = Text(label, style: SlowlightTypography.button);
    if (icon != null) {
      return Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
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
    final child = _buildChild();
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
      constraints: const BoxConstraints(minHeight: 44),
      child: button,
    );
  }
}
