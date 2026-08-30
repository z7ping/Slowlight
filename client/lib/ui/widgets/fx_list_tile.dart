import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../typography_tokens.dart';
import 'fx_cursor.dart';

/// FxListTile — 统一列表行。
///
/// 保留 Material ListTile 常用命名参数作为迁移兼容层，但视觉与交互始终由 Fx 控制。
class FxListTile extends StatelessWidget {
  const FxListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.onFocusChange,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.contentPadding,
    this.minHeight = 52,
    this.minTileHeight,
    this.showDivider = false,
    this.titleStyle,
    this.subtitleStyle,
    this.titleTextStyle,
    this.subtitleTextStyle,
    this.leadingAndTrailingTextStyle,
    this.enabled = true,
    this.selected = false,
    this.tileColor,
    this.selectedTileColor,
    this.textColor,
    this.selectedColor,
    this.iconColor,
    this.focusColor,
    this.hoverColor,
    this.splashColor,
    this.dense = false,
    this.isThreeLine = false,
    this.visualDensity,
    this.horizontalTitleGap,
    this.minVerticalPadding,
    this.minLeadingWidth,
    this.shape,
    this.selectedShape,
    this.mouseCursor,
    this.enableFeedback = true,
    this.autofocus = false,
    this.titleAlignment,
    this.internalAddSemanticForOnTap,
  })  : assert(title is String || title is Widget),
        assert(subtitle == null || subtitle is String || subtitle is Widget);

  final Object title;
  final Object? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFocusChange;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? contentPadding;
  final double minHeight;
  final double? minTileHeight;
  final bool showDivider;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final TextStyle? titleTextStyle;
  final TextStyle? subtitleTextStyle;
  final TextStyle? leadingAndTrailingTextStyle;
  final bool enabled;
  final bool selected;
  final Color? tileColor;
  final Color? selectedTileColor;
  final Color? textColor;
  final Color? selectedColor;
  final Color? iconColor;
  final Color? focusColor;
  final Color? hoverColor;
  final Color? splashColor;
  final bool dense;
  final bool isThreeLine;
  final VisualDensity? visualDensity;
  final double? horizontalTitleGap;
  final double? minVerticalPadding;
  final double? minLeadingWidth;
  final ShapeBorder? shape;
  final ShapeBorder? selectedShape;
  final MouseCursor? mouseCursor;
  final bool enableFeedback;
  final bool autofocus;
  final ListTileTitleAlignment? titleAlignment;
  final bool? internalAddSemanticForOnTap;

  Widget _content(
    Object value, {
    required TextStyle fallbackStyle,
  }) {
    if (value is Widget) return value;
    return Text(value as String, style: fallbackStyle);
  }

  BorderRadius _borderRadius() {
    final effectiveShape = selected ? selectedShape ?? shape : shape;
    if (effectiveShape is RoundedRectangleBorder &&
        effectiveShape.borderRadius is BorderRadius) {
      return effectiveShape.borderRadius as BorderRadius;
    }
    return BorderRadius.circular(AppTheme.radiusMd);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveForeground = selected
        ? selectedColor ?? textColor ?? theme.colorScheme.onSurface
        : textColor ?? theme.colorScheme.onSurface;
    final effectivePadding = contentPadding ?? padding;
    final gap = horizontalTitleGap ?? AppTheme.spaceSm;
    final leadingWidth = minLeadingWidth ?? 0;
    final showSubtitle = subtitle is Widget ||
        (subtitle is String && (subtitle! as String).isNotEmpty);
    final baseMinHeight = minTileHeight ?? (dense ? minHeight - 8 : minHeight);
    final effectiveMinHeight = visualDensity?.effectiveConstraints(
          BoxConstraints(minHeight: baseMinHeight),
        ).minHeight ??
        baseMinHeight;

    final leadingWidget = leading == null
        ? null
        : DefaultTextStyle.merge(
            style: leadingAndTrailingTextStyle,
            child: IconTheme(
              data: IconThemeData(
                color: iconColor ??
                    (selected
                        ? selectedColor
                        : theme.colorScheme.onSurfaceVariant),
              ),
              child: leading!,
            ),
          );
    final trailingWidget = trailing == null
        ? null
        : DefaultTextStyle.merge(
            style: leadingAndTrailingTextStyle,
            child: trailing!,
          );

    final row = Container(
      constraints: BoxConstraints(minHeight: effectiveMinHeight),
      padding: effectivePadding,
      decoration: BoxDecoration(
        color: selected ? selectedTileColor ?? tileColor : tileColor,
        borderRadius: _borderRadius(),
        border: showDivider
            ? Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leadingWidget != null) ...[
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: leadingWidth),
              child: leadingWidget,
            ),
            SizedBox(width: gap),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DefaultTextStyle.merge(
                  style: TextStyle(color: effectiveForeground),
                  child: _content(
                    title,
                    fallbackStyle: titleTextStyle ??
                        titleStyle ??
                        SlowlightTypography.secondary(context).copyWith(
                          fontWeight: FontWeight.w600,
                          color: effectiveForeground,
                        ),
                  ),
                ),
                if (showSubtitle) ...[
                  const SizedBox(height: 2),
                  _content(
                    subtitle!,
                    fallbackStyle: subtitleTextStyle ??
                        subtitleStyle ??
                        SlowlightTypography.caption(context).copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (trailingWidget != null) ...[
            SizedBox(width: gap),
            trailingWidget,
          ],
        ],
      ),
    );
    if ((!enabled) || (onTap == null && onLongPress == null)) {
      return Opacity(opacity: enabled ? 1 : .5, child: row);
    }
    return FxInkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      onFocusChange: onFocusChange,
      mouseCursor: mouseCursor,
      enableFeedback: enableFeedback,
      autofocus: autofocus,
      focusColor: focusColor,
      hoverColor: hoverColor,
      splashColor: splashColor,
      borderRadius: _borderRadius(),
      child: row,
    );
  }
}
