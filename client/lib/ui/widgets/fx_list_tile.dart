import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../typography_tokens.dart';
import 'fx_cursor.dart';

/// FxListTile — 统一列表行。
///
/// 用于设置、选择列表、轻量内容列表等常见单行/双行场景，避免业务页面
/// 直接依赖 Material ListTile 的默认密度与排版。
class FxListTile extends StatelessWidget {
  final Object title;
  final Object? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double minHeight;
  final bool showDivider;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;

  const FxListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.minHeight = 52,
    this.showDivider = false,
    this.titleStyle,
    this.subtitleStyle,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleValue = subtitle;
    final showSubtitle = subtitleValue is Widget ||
        (subtitleValue is String && subtitleValue.isNotEmpty);
    final row = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: padding,
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppTheme.spaceSm),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _content(
                  context,
                  title,
                  fallbackStyle: titleStyle ??
                      SlowlightTypography.secondary(context).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (showSubtitle) ...[
                  const SizedBox(height: 2),
                  _content(
                    context,
                    subtitleValue!,
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
            const SizedBox(width: AppTheme.spaceSm),
            trailing!,
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return FxInkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: row,
    );
  }
}
