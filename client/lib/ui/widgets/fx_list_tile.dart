import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../typography_tokens.dart';
import 'fx_cursor.dart';

/// FxListTile — 统一列表行。
///
/// 用于设置、选择列表、轻量内容列表等常见单行/双行场景。保留 Material
/// ListTile 的常用命名参数作为迁移兼容层，但视觉与交互始终由 Fx 控制。
class FxListTile extends StatelessWidget {
  final Object title;
  final Object? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? contentPadding;
  final double minHeight;
  final bool showDivider;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final bool enabled;
  final bool selected;
  final Color? tileColor;
  final Color? selectedTileColor;
  final Color? textColor;
  final Color? selectedColor;
  final Color? iconColor;
  final bool dense;
  final double? horizontalTitleGap;
  final double? minLeadingWidth;
  final ShapeBorder? shape;
  final ShapeBorder? selectedShape;
  final MouseCursor? mouseCursor;
  final bool enableFeedback;

  const FxListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.contentPadding,
    this.minHeight = 52,
    this.showDivider = false,
    this.titleStyle,
    this.subtitleStyle,
    this.enabled = true,
    this.selected = false,
    this.tileColor,
    this.selectedTileColor,
    this.textColor,
    this.selectedColor,
    this.iconColor,
    this.dense = false,
    this.horizontalTitleGap,
    this.minLeadingWidth,
    this.shape,
    this.selectedShape,
    this.mouseCursor,
    this.enableFeedback = true,
  })  : assert(title is String || title is Widget),
        assert(subtitle == null || subtitle is String || subtitle is Widget);

  Widget _content(
    BuildContext context,
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

    final row = Container(
      constraints: BoxConstraints(minHeight: dense ? minHeight - 8 : minHeight),
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
          if (leading != null) ...[
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: leadingWidth),
              child: IconTheme(
                data: IconThemeData(
                  color: iconColor ??
                      (selected
                          ? selectedColor
                          : theme.colorScheme.onSurfaceVariant),
                ),
                child: leading!,
              ),
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
                    context,
                    title,
                    fallbackStyle: titleStyle ??
                        SlowlightTypography.secondary(context).copyWith(
                          fontWeight: FontWeight.w600,
                          color: effectiveForeground,
                        ),
                  ),
                ),
                if (showSubtitle) ...[
                  const SizedBox(height: 2),
                  _content(
                    context,
                    subtitle!,
                    fallbackStyle: subtitleStyle ??
                        SlowlightTypography.caption(context).copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: gap),
            trailing!,
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
      mouseCursor: mouseCursor,
      enableFeedback: enableFeedback,
      borderRadius: _borderRadius(),
      child: row,
    );
  }
}
