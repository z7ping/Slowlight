import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'fx_cursor.dart';
import 'fx_tooltip.dart';

/// Slowlight 统一弹出菜单项。
class FxMenuItem<T> extends StatelessWidget {
  const FxMenuItem({
    super.key,
    this.value,
    required this.child,
    this.onTap,
    this.enabled = true,
    this.height = 40,
    this.padding,
    this.textStyle,
    this.labelTextStyle,
    this.mouseCursor,
  });

  final T? value;
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final double height;
  final EdgeInsetsGeometry? padding;
  final TextStyle? textStyle;
  final WidgetStateProperty<TextStyle?>? labelTextStyle;
  final MouseCursor? mouseCursor;

  @override
  Widget build(BuildContext context) {
    final style = labelTextStyle?.resolve(const <WidgetState>{}) ?? textStyle;
    if (style == null) return child;
    return DefaultTextStyle.merge(style: style, child: child);
  }
}

typedef FxMenuItemBuilder<T> = List<FxMenuItem<T>> Function(BuildContext context);

/// Slowlight 统一弹出菜单。
///
/// API 兼容项目中既有 PopupMenuButton / PopupMenuItem 常用调用形态；
/// 视觉与浮层统一由 shadcn_ui 提供。
class FxMenu<T> extends StatefulWidget {
  const FxMenu({
    super.key,
    required this.itemBuilder,
    this.initialValue,
    this.onSelected,
    this.onCanceled,
    this.onOpened,
    this.tooltip,
    this.child,
    this.icon,
    this.iconSize,
    this.enabled = true,
    this.padding = const EdgeInsets.all(8),
    this.offset = Offset.zero,
    this.constraints,
    this.requestFocus,
    this.enableFeedback,
    this.elevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.splashRadius,
    this.shape,
    this.color,
    this.menuPadding,
    this.position,
    this.clipBehavior = Clip.none,
    this.useRootNavigator = false,
    this.popUpAnimationStyle,
    this.style,
  });

  final FxMenuItemBuilder<T> itemBuilder;
  final T? initialValue;
  final ValueChanged<T>? onSelected;
  final VoidCallback? onCanceled;
  final VoidCallback? onOpened;
  final String? tooltip;
  final Widget? child;
  final Widget? icon;
  final double? iconSize;
  final bool enabled;
  final EdgeInsetsGeometry padding;
  final Offset offset;
  final BoxConstraints? constraints;
  final bool? requestFocus;
  final bool? enableFeedback;

  // 兼容旧 PopupMenuButton 调用；Fx 视觉不直接透传 Material 样式。
  final double? elevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final double? splashRadius;
  final ShapeBorder? shape;
  final Color? color;
  final EdgeInsetsGeometry? menuPadding;
  final Object? position;
  final Clip clipBehavior;
  final bool useRootNavigator;
  final Object? popUpAnimationStyle;
  final Object? style;

  @override
  State<FxMenu<T>> createState() => _FxMenuState<T>();
}

class _FxMenuState<T> extends State<FxMenu<T>> {
  late final ShadPopoverController _controller;
  bool _wasOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = ShadPopoverController();
    _controller.addListener(_handleVisibilityChanged);
  }

  void _handleVisibilityChanged() {
    final open = _controller.isOpen;
    if (open && !_wasOpen) widget.onOpened?.call();
    if (!open && _wasOpen) widget.onCanceled?.call();
    _wasOpen = open;
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleVisibilityChanged)
      ..dispose();
    super.dispose();
  }

  void _select(FxMenuItem<T> item) {
    if (!item.enabled) return;
    item.onTap?.call();
    _wasOpen = false;
    _controller.hide();
    widget.onSelected?.call(item.value as T);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trigger =
        widget.child ?? widget.icon ?? Icon(Icons.more_vert, size: widget.iconSize ?? 20);

    Widget clickable = Padding(
      padding: widget.child == null ? widget.padding : EdgeInsets.zero,
      child: trigger,
    );
    clickable = FxInkWell(
      onTap: widget.enabled ? _controller.toggle : null,
      enableFeedback: widget.enableFeedback ?? true,
      borderRadius: BorderRadius.circular(8),
      child: clickable,
    );
    if (widget.tooltip case final message? when message.isNotEmpty) {
      clickable = FxTooltip(message: message, child: clickable);
    }

    return ShadPopover(
      controller: _controller,
      padding: EdgeInsets.zero,
      child: clickable,
      popover: (popoverContext) {
        final items = widget.itemBuilder(popoverContext);
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              FxInkWell(
                onTap: item.enabled ? () => _select(item) : null,
                mouseCursor: item.mouseCursor,
                hoverColor: theme.colorScheme.onSurface.withValues(alpha: .06),
                focusColor: theme.colorScheme.onSurface.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(6),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: item.height),
                  child: Padding(
                    padding: item.padding ??
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Opacity(
                      opacity: item.enabled ? 1 : .5,
                      child: item,
                    ),
                  ),
                ),
              ),
          ],
        );
        return ConstrainedBox(
          constraints: widget.constraints ??
              const BoxConstraints(minWidth: 160, maxWidth: 320),
          child: content,
        );
      },
    );
  }
}
