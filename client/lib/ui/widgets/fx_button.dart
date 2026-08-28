import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
    if (icon != null) {
      return Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text(label),
        ],
      );
    }
    return Text(label);
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
    switch (variant) {
      case FxButtonVariant.primary:
        return ShadButton(
          onPressed: onPressed,
          size: _shadSize,
          child: child,
        );
      case FxButtonVariant.secondary:
        return ShadButton.secondary(
          onPressed: onPressed,
          size: _shadSize,
          child: child,
        );
      case FxButtonVariant.outline:
        return ShadButton.outline(
          onPressed: onPressed,
          size: _shadSize,
          child: child,
        );
      case FxButtonVariant.ghost:
        return ShadButton.ghost(
          onPressed: onPressed,
          size: _shadSize,
          child: child,
        );
      case FxButtonVariant.destructive:
        return ShadButton.destructive(
          onPressed: onPressed,
          size: _shadSize,
          child: child,
        );
      case FxButtonVariant.link:
        return ShadButton.link(
          onPressed: onPressed,
          size: _shadSize,
          child: child,
        );
    }
  }
}
