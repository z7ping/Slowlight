import 'package:flutter/material.dart';

import '../layout_tokens.dart';
import '../typography_tokens.dart';
import 'fx_cursor.dart';

/// Slowlight 统一可展开列表块。
///
/// 保留 ExpansionTile 的常用业务参数，但不再依赖 Material ExpansionTile 的
/// 默认视觉；展开行为由 Flutter 基础动画实现，视觉由 Slowlight Token 控制。
class FxExpansionTile extends StatefulWidget {
  const FxExpansionTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.children = const [],
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    this.tilePadding,
    this.childrenPadding,
    this.backgroundColor,
    this.collapsedBackgroundColor,
    this.textColor,
    this.collapsedTextColor,
    this.iconColor,
    this.collapsedIconColor,
    this.enabled = true,
    this.dense = false,
    this.showTrailingIcon = true,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final List<Widget> children;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final EdgeInsetsGeometry? tilePadding;
  final EdgeInsetsGeometry? childrenPadding;
  final Color? backgroundColor;
  final Color? collapsedBackgroundColor;
  final Color? textColor;
  final Color? collapsedTextColor;
  final Color? iconColor;
  final Color? collapsedIconColor;
  final bool enabled;
  final bool dense;
  final bool showTrailingIcon;

  @override
  State<FxExpansionTile> createState() => _FxExpansionTileState();
}

class _FxExpansionTileState extends State<FxExpansionTile> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  void _toggle() {
    if (!widget.enabled) return;
    setState(() => _expanded = !_expanded);
    widget.onExpansionChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = _expanded
        ? widget.textColor ?? theme.colorScheme.onSurface
        : widget.collapsedTextColor ?? theme.colorScheme.onSurface;
    final iconForeground = _expanded
        ? widget.iconColor ?? theme.colorScheme.onSurfaceVariant
        : widget.collapsedIconColor ?? theme.colorScheme.onSurfaceVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: _expanded
            ? widget.backgroundColor
            : widget.collapsedBackgroundColor,
        borderRadius: BorderRadius.circular(SlowlightRadius.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FxInkWell(
            onTap: widget.enabled ? _toggle : null,
            borderRadius: BorderRadius.circular(SlowlightRadius.md),
            child: Padding(
              padding: widget.tilePadding ??
                  EdgeInsets.symmetric(
                    horizontal: SlowlightSpacing.xl,
                    vertical: widget.dense ? 8 : 12,
                  ),
              child: Row(
                children: [
                  if (widget.leading != null) ...[
                    IconTheme(
                      data: IconThemeData(color: iconForeground),
                      child: widget.leading!,
                    ),
                    const SizedBox(width: SlowlightSpacing.md),
                  ],
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style: SlowlightTypography.componentSecondary(
                        context,
                      ).copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          widget.title,
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 2),
                            DefaultTextStyle.merge(
                              style: SlowlightTypography.caption(context)
                                  .copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              child: widget.subtitle!,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (widget.trailing != null)
                    widget.trailing!
                  else if (widget.showTrailingIcon)
                    AnimatedRotation(
                      turns: _expanded ? .5 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: iconForeground,
                      ),
                    ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: _expanded
                ? Padding(
                    padding: widget.childrenPadding ??
                        const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: widget.children,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
