import 'fx_cursor.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// FxCard — 卡片组件
class FxCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;
  final double? borderRadius;
  final EdgeInsets? margin;
  final Border? border;
  final List<BoxShadow>? boxShadow;
  final bool expanded;
  final Key? _deprecatedCardKey;

  const FxCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
    this.borderRadius,
    this.margin,
    this.border,
    this.boxShadow,
    this.expanded = false,
    @Deprecated('Pass key directly to FxCard constructor instead')
    Key? cardKey,
  }) : _deprecatedCardKey = cardKey;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius != null
        ? BorderRadius.circular(borderRadius!)
        : null;
    final resolvedPadding =
        (padding ?? const EdgeInsets.all(16)).resolve(Directionality.of(context));
    final hasShadTheme =
        context.dependOnInheritedWidgetOfExactType<ShadTheme>() != null;

    final content = Align(
      alignment: Alignment.topCenter,
      child: child,
    );

    Widget card;
    if (hasShadTheme) {
      card = ShadCard(
        key: _deprecatedCardKey,
        padding: resolvedPadding,
        backgroundColor: color,
        radius: radius,
        border: border,
        columnMainAxisAlignment: MainAxisAlignment.start,
        child: content,
      );
    } else {
      card = Container(
        key: _deprecatedCardKey,
        padding: resolvedPadding,
        decoration: BoxDecoration(
          color: color ?? Theme.of(context).colorScheme.surface,
          borderRadius: radius,
          border: border,
        ),
        child: content,
      );
    }

    if (boxShadow != null && radius != null) {
      card = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: boxShadow,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: card,
        ),
      );
    }

    if (expanded) {
      card = SizedBox(width: double.infinity, child: card);
    }

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }

    if (onTap != null) {
      return FxGestureDetector(onTap: onTap, child: card);
    }
    return card;
  }
}
