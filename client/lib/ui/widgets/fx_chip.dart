import 'fx_cursor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../typography_tokens.dart';

/// FxChip — 标签/徽章组件。
///
/// 默认仍以 ShadBadge 为视觉基础；需要 secondary / outline / destructive
/// 或迁移旧组件既定视觉时，由 Fx 层统一解析语义，不让页面自行手写 Chip。
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasExplicitVisualOverride = backgroundColor != null ||
        foregroundColor != null ||
        borderRadius != null ||
        padding != null;

    Widget badge;
    if (!hasExplicitVisualOverride && variant == FxChipVariant.primary) {
      badge = ShadBadge(child: _content(context));
    } else {
      final resolvedBackground = backgroundColor ?? switch (variant) {
        FxChipVariant.primary => scheme.primary,
        FxChipVariant.secondary => scheme.surfaceContainerHighest,
        FxChipVariant.outline => Colors.transparent,
        FxChipVariant.destructive => scheme.errorContainer,
      };
      final resolvedForeground = foregroundColor ?? switch (variant) {
        FxChipVariant.primary => scheme.onPrimary,
        FxChipVariant.secondary => scheme.onSurfaceVariant,
        FxChipVariant.outline => scheme.onSurface,
        FxChipVariant.destructive => scheme.onErrorContainer,
      };
      final outlineBorder = variant == FxChipVariant.outline
          ? Border.all(color: scheme.outlineVariant)
          : null;

      badge = Container(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: resolvedBackground,
          border: outlineBorder,
          borderRadius: BorderRadius.circular(borderRadius ?? 999),
        ),
        child: _content(context, color: resolvedForeground),
      );
    }

    if (onTap != null) {
      final android =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      badge = ConstrainedBox(
        constraints: BoxConstraints(minHeight: android ? 44 : 32),
        child: Align(alignment: Alignment.center, child: badge),
      );
      badge = FxGestureDetector(onTap: onTap, child: badge);
    }
    return badge;
  }
}

enum FxChipVariant { primary, secondary, outline, destructive }
