import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../layout_tokens.dart';
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
typedef FxMenuContentBuilder = Widget Function(
  BuildContext context,
  VoidCallback dismiss,
);

/// Slowlight 统一弹出菜单。
///
/// API 兼容项目中既有 PopupMenuButton / PopupMenuItem 常用调用形态；
/// 视觉与浮层统一由 shadcn_ui 提供。
class FxMenu<T> extends StatefulWidget {
  const FxMenu({
    super.key,
    this.itemBuilder,
    this.contentBuilder,
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
    this.preferAbove = false,
    this.position,
    this.clipBehavior = Clip.none,
    this.useRootNavigator = false,
    this.popUpAnimationStyle,
    this.style,
  });

  final FxMenuItemBuilder<T>? itemBuilder;
  /// Reuse the same anchored ShadPopover for interactive multi-select content.
  final FxMenuContentBuilder? contentBuilder;
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
  /// Open above the trigger. Rich quick menus use Flutter's native popup
  /// route with keyboard-safe height and scrolling; ordinary Shad popovers
  /// keep their previous behavior.
  final bool preferAbove;
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
  bool _routeMenuOpen = false;
  final GlobalKey _quickAnchorKey = GlobalKey();

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

  BoxConstraints _effectiveConstraints(BoxConstraints base) {
    if (!widget.preferAbove) return base;
    final target = context.findRenderObject();
    if (target is! RenderBox || !target.hasSize || !target.attached) {
      return base;
    }
    // Legacy simple-menu path: constrain by the visible space above the
    // trigger. Rich task menus use _openKeyboardSafeMenu instead.
    final triggerTop = target.localToGlobal(Offset.zero).dy;
    final available = math.max(
      SlowlightControlSize.minTouchTarget,
      triggerTop - MediaQuery.viewPaddingOf(context).top - 20,
    );
    final height = math.min(base.maxHeight, available);
    return base.copyWith(
      minHeight: math.min(base.minHeight, height),
      maxHeight: height,
    );
  }

  /// The locked shadcn_ui 0.26.5 auto anchor measures against the entire
  /// overlay, not the unobscured area above Android's IME. Use Flutter's
  /// built-in popup route for keyboard-preserving task quick menus: its
  /// positioning delegate clamps horizontal bounds, while the explicit
  /// above-trigger position and bounded scroll content avoid the IME.
  Future<void> _openKeyboardSafeMenu() async {
    if (_routeMenuOpen || !mounted || !widget.enabled) return;
    final navigator = Navigator.of(context, rootNavigator: widget.useRootNavigator);
    final overlay = navigator.overlay?.context.findRenderObject();
    final target = _quickAnchorKey.currentContext?.findRenderObject();
    if (overlay is! RenderBox || target is! RenderBox ||
        !target.attached || !target.hasSize) return;

    final targetTopLeft =
        target.localToGlobal(Offset.zero, ancestor: overlay);
    final width = math.min(
      widget.constraints?.maxWidth ?? 220.0,
      math.max(SlowlightControlSize.minTouchTarget, overlay.size.width - 24),
    );
    final topSafe = MediaQuery.paddingOf(context).top + 8;
    final availableAbove = math.max(
      SlowlightControlSize.minTouchTarget,
      targetTopLeft.dy - topSafe - 8,
    );
    final height = math.min(
      widget.constraints?.maxHeight ?? 320.0,
      availableAbove,
    );
    final x = (targetTopLeft.dx + (target.size.width - width) / 2)
        .clamp(12.0, math.max(12.0, overlay.size.width - width - 12))
        .toDouble();
    final y = math.max(topSafe, targetTopLeft.dy - height - 8);
    final position = RelativeRect.fromLTRB(
      x, y, overlay.size.width - x - width, overlay.size.height - y - height,
    );

    _routeMenuOpen = true;
    widget.onOpened?.call();
    try {
      await showMenu<Object?>(
        context: context,
        useRootNavigator: widget.useRootNavigator,
        requestFocus: false,
        position: position,
        constraints: BoxConstraints.tightFor(width: width, height: height),
        menuPadding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: .16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SlowlightRadius.lg),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        items: [
          PopupMenuItem<Object?>(
            enabled: false,
            padding: EdgeInsets.zero,
            height: 0,
            child: SizedBox(
              width: width,
              height: height,
              child: Builder(
                builder: (routeContext) => DefaultTextStyle.merge(
                  textAlign: TextAlign.start,
                  child: widget.contentBuilder!(
                    routeContext,
                    () => Navigator.of(routeContext).pop(),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    } finally {
      _routeMenuOpen = false;
      if (mounted) widget.onCanceled?.call();
    }
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
        widget.child ?? widget.icon ?? Icon(LucideIcons.ellipsis, size: widget.iconSize ?? 20);

    final keyboardSafe = widget.preferAbove && widget.contentBuilder != null;
    Widget clickable = Padding(
      padding: widget.child == null ? widget.padding : EdgeInsets.zero,
      child: trigger,
    );
    clickable = FxInkWell(
      onTap: widget.enabled
          ? (keyboardSafe ? _openKeyboardSafeMenu : _controller.toggle)
          : null,
      enableFeedback: widget.enableFeedback ?? true,
      borderRadius: BorderRadius.circular(8),
      child: clickable,
    );
    if (widget.tooltip case final message? when message.isNotEmpty) {
      clickable = FxTooltip(message: message, child: clickable);
    }

    if (keyboardSafe) {
      return KeyedSubtree(key: _quickAnchorKey, child: clickable);
    }

    return ShadPopover(
      controller: _controller,
      padding: EdgeInsets.zero,
      // ShadAnchorAuto uses Flutter's positionDependentBox, so the whole
      // popup (including list/tags) stays inside the screen horizontally.
      // Align the measured popup above the trigger without a hand-rolled
      // left/right offset. The height constraint still leaves room for IME.
      anchor: widget.preferAbove
          ? const ShadAnchorAuto(
              targetAnchor: Alignment.topCenter,
              followerAnchor: Alignment.topCenter,
              offset: Offset(0, -8),
            )
          : null,
      child: clickable,
      popover: (popoverContext) {
        final custom = widget.contentBuilder;
        if (custom != null) {
          return ConstrainedBox(
            constraints: _effectiveConstraints(widget.constraints ??
                const BoxConstraints(minWidth: 160, maxWidth: 320)),
            // ShadPopover (0.26.5) centers its inherited DefaultTextStyle.
            // Menus are selection lists: override the inherited alignment
            // here once, preserving Shad's foreground style and the caller's
            // explicitly aligned content (buttons, icons, etc).
            child: DefaultTextStyle.merge(
              textAlign: TextAlign.start,
              child: custom(popoverContext, _controller.hide),
            ),
          );
        }
        final items = widget.itemBuilder?.call(popoverContext) ?? [];
        final mobile = SlowlightPlatformDensity.usesMobileTouchTargets;
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
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  constraints: BoxConstraints(
                    minHeight: mobile &&
                            item.height < SlowlightControlSize.minTouchTarget
                        ? SlowlightControlSize.minTouchTarget
                        : item.height,
                  ),
                  padding: item.padding ??
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: item.value != null && item.value == widget.initialValue
                        ? theme.colorScheme.surfaceContainerHighest
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Opacity(
                    opacity: item.enabled ? 1 : .5,
                    child: item,
                  ),
                ),
              ),
          ],
        );
        // Simple selection menus share a compact, bounded popover.
        // Rich custom popovers retain their own explicit size contract.
        return ConstrainedBox(
          constraints: _effectiveConstraints(widget.constraints ??
              const BoxConstraints(minWidth: 168, maxWidth: 220)),
          child: Padding(
            padding: widget.menuPadding ?? const EdgeInsets.all(5),
            child: DefaultTextStyle.merge(
              textAlign: TextAlign.start,
              child: content,
            ),
          ),
        );
      },
    );
  }
}
