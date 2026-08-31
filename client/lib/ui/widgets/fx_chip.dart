import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../app_theme.dart';
import '../layout_tokens.dart';
import '../typography_tokens.dart';
import 'fx_cursor.dart';

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
  final Color? borderColor;
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
    this.borderColor,
    this.borderRadius,
    this.padding,
  });

  Widget _content(BuildContext context, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: SlowlightIconSize.xs, color: color),
          const SizedBox(width: SlowlightSpacing.xs),
        ],
        Flexible(
          child: Text(
            label,
            style: SlowlightTypography.chip(context).copyWith(color: color),
          ),
        ),
        if (onDeleted != null) ...[
          const SizedBox(width: SlowlightSpacing.xs),
          FxGestureDetector(
            onTap: onDeleted,
            child: SizedBox(
              width: SlowlightControlSize.minTouchTarget,
              height: SlowlightControlSize.minTouchTarget,
              child: Center(
                child: Icon(
                  Icons.close,
                  size: SlowlightIconSize.xs,
                  color: color,
                ),
              ),
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
    final hasExplicitVisualOverride =
        backgroundColor != null ||
        foregroundColor != null ||
        borderColor != null ||
        borderRadius != null ||
        padding != null;

    Widget badge;
    if (!hasExplicitVisualOverride && variant == FxChipVariant.primary) {
      badge = ShadBadge(child: _content(context));
    } else {
      final resolvedBackground = backgroundColor ??
          switch (variant) {
            FxChipVariant.primary => scheme.primary,
            FxChipVariant.secondary => scheme.surfaceContainerHighest,
            FxChipVariant.outline => Colors.transparent,
            FxChipVariant.destructive => scheme.errorContainer,
          };
      final resolvedForeground = foregroundColor ??
          switch (variant) {
            FxChipVariant.primary => scheme.onPrimary,
            FxChipVariant.secondary => scheme.onSurface,
            FxChipVariant.outline => scheme.onSurface,
            FxChipVariant.destructive => scheme.onErrorContainer,
          };
      final resolvedBorder = borderColor != null
          ? Border.all(color: borderColor!)
          : variant == FxChipVariant.outline
          ? Border.all(color: scheme.outline)
          : null;

      badge = Container(
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: resolvedBackground,
          border: resolvedBorder,
          borderRadius: BorderRadius.circular(
            borderRadius ?? SlowlightRadius.pill,
          ),
        ),
        child: _content(context, color: resolvedForeground),
      );
    }

    if (onTap != null) {
      final android =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      badge = ConstrainedBox(
        constraints: BoxConstraints(
          minHeight:
              android
                  ? SlowlightControlSize.minTouchTarget
                  : SlowlightControlSize.buttonSm,
        ),
        child: Align(alignment: Alignment.center, child: badge),
      );
      badge = FxGestureDetector(onTap: onTap, child: badge);
    }
    return badge;
  }
}

/// FxChoiceChip — 清单、优先级、标签等“可选择”项目的统一视觉。
///
/// 选中状态同时使用底色、文字色和边框表达，避免仅靠很浅的背景色区分。
class FxChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? selectionColor;

  const FxChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.icon,
    this.selectionColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectedColor = selectionColor ?? activePalette.accent;
    final selectedAlpha = theme.brightness == Brightness.dark ? .22 : .13;
    return FxChip(
      label: label,
      icon: icon,
      variant: FxChipVariant.outline,
      backgroundColor:
          selected
              ? selectedColor.withValues(alpha: selectedAlpha)
              : scheme.surfaceContainerLowest,
      foregroundColor: selected ? selectedColor : scheme.onSurface,
      borderColor: selected ? selectedColor : scheme.outline,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      onTap: onTap,
    );
  }
}

enum FxChipVariant { primary, secondary, outline, destructive }
