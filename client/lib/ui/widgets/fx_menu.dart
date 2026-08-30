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
    this.enabled = true,
    this.height = 40,
    this.padding,
  });

  final T? value;
  final Widget child;
  final bool enabled;
  final double height;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => child;
}

typedef FxMenuItemBuilder<T> = List<FxMenuItem<T>> Function(BuildContext context);

/// Slowlight 统一弹出菜单。
///
/// API 有意兼容项目中既有 PopupMenuButton / PopupMenuItem 的常用调用形态，
/// 视觉与浮层能力统一由 shadcn_ui 提供，业务代码不再直接依赖 Material 菜单。
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

  /// 兼容旧调用。实际定位交给 ShadPopover 的自动锚点策略。
  final Offset offset;
  final BoxConstraints? constraints;
  final bool? requestFocus;
  final bool? enableFeedback;

  @override
  State<FxMenu<T>> createState() => _FxMenuState<T>();
}

class _FxMenuState<T> extends State<FxMenu<T>> {
  late final ShadPopoverController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ShadPopoverController();
    _controller.addListener(_handleVisibilityChanged);
  }

  bool _wasOpen = false;

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
    _wasOpen = false;
    _controller.hide();
    widget.onSelected?.call(item.value as T);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trigger = widget.child ??
        widget.icon ??
        Icon(Icons.more_vert, size: widget.iconSize ?? 20);

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
                      child: item.child,
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
