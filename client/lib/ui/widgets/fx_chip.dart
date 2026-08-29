import 'fx_cursor.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../typography_tokens.dart';

/// FxChip — 标签/徽章组件。
///
/// 常规场景继续以 ShadBadge 为视觉基础；迁移旧组件时如确有既定视觉语义，
/// 可通过受控的颜色、圆角和内边距覆盖，不在业务页面重新手写 Chip。
class FxChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final VoidCallback? onDeleted;
  final FxChipVariant variant;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? borderRadius;
  final EdgeInsetsGeometry? padding;

  const FxChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.onDeleted,
    this.variant = FxChipVariant.primary,
    this.backgroundColor,
    this.foregroundColor,
    this.borderRadius,
    this.padding,
  });

  Widget _content(BuildContext context, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            style: SlowlightTypography.caption(context).copyWith(
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ),
        if (onDeleted != null) ...[
          const SizedBox(width: 4),
          FxGestureDetector(
            onTap: onDeleted,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(child: Icon(Icons.close, size: 14, color: color)),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasVisualOverride = backgroundColor != null ||
        foregroundColor != null ||
        borderRadius != null ||
        padding != null;

    Widget badge;
    if (hasVisualOverride) {
      badge = Container(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(borderRadius ?? 999),
        ),
        child: _content(context, color: foregroundColor),
      );
    } else {
      badge = ShadBadge(child: _content(context));
    }

    if (onTap != null) {
      badge = FxGestureDetector(onTap: onTap, child: badge);
    }
    return badge;
  }
}

enum FxChipVariant { primary, secondary, outline, destructive }
