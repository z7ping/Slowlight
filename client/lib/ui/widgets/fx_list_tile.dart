import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../typography_tokens.dart';
import 'fx_cursor.dart';

/// FxListTile — 统一列表行。
///
/// 用于设置、选择列表、轻量内容列表等常见单行/双行场景，避免业务页面
/// 直接依赖 Material ListTile 的默认密度与排版。
class FxListTile extends StatelessWidget {
  final String title;
  final String? subtitle;
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
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                Text(
                  title,
                  style: titleStyle ??
                      SlowlightTypography.secondary(context).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: subtitleStyle ??
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
