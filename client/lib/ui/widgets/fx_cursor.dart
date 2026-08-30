import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

bool get _isDesktopPlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

/// Slowlight 统一可点击交互表面。
///
/// 不再继承 Material [InkWell]。点击/悬停由 shadcn_ui 的
/// [ShadGestureDetector] 负责，键盘焦点与 Activate 行为仍使用 Flutter
/// 基础设施。保留原 InkWell 常用参数是为了平滑迁移现有业务调用。
class FxInkWell extends StatefulWidget {
  const FxInkWell({
    super.key,
    this.child,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.mouseCursor,
    this.borderRadius,
    this.highlightColor,
    this.splashColor,
    this.hoverColor,
    this.focusColor,
    this.splashFactory,
    this.radius,
    this.overlayColor,
    this.enableFeedback = true,
    this.excludeFromSemantics = false,
    this.canRequestFocus = true,
    this.autofocus = false,
    this.focusNode,
    this.statesController,
  });

  final Widget? child;
  final GestureTapCallback? onTap;
  final GestureTapCallback? onDoubleTap;
  final GestureLongPressCallback? onLongPress;
  final ValueChanged<bool>? onHover;
  final ValueChanged<bool>? onFocusChange;
  final MouseCursor? mouseCursor;
  final BorderRadius? borderRadius;
  final Color? highlightColor;
  final Color? splashColor;
  final Color? hoverColor;
  final Color? focusColor;

  /// 兼容旧调用；FxInkWell 不创建 Material splash。
  final InteractiveInkFeatureFactory? splashFactory;

  /// 兼容旧调用；FxInkWell 的状态覆盖层由 [borderRadius] 限制。
  final double? radius;
  final WidgetStateProperty<Color?>? overlayColor;
  final bool enableFeedback;
  final bool excludeFromSemantics;
  final bool canRequestFocus;
  final bool autofocus;
  final FocusNode? focusNode;
  final WidgetStatesController? statesController;

  @override
  State<FxInkWell> createState() => _FxInkWellState();
}

class _FxInkWellState extends State<FxInkWell> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  Set<WidgetState> get _states => {
        if (_hovered) WidgetState.hovered,
        if (_focused) WidgetState.focused,
        if (_pressed) WidgetState.pressed,
      };

  void _setStateFlag(WidgetState state, bool value) {
    final changed = switch (state) {
      WidgetState.hovered => _hovered != value,
      WidgetState.focused => _focused != value,
      WidgetState.pressed => _pressed != value,
      _ => false,
    };
    if (!changed) return;
    setState(() {
      switch (state) {
        case WidgetState.hovered:
          _hovered = value;
        case WidgetState.focused:
          _focused = value;
        case WidgetState.pressed:
          _pressed = value;
        default:
          break;
      }
    });
    widget.statesController?.update(state, value);
  }

  Color? get _stateColor {
    final resolved = widget.overlayColor?.resolve(_states);
    if (resolved != null) return resolved;
    if (_pressed) return widget.highlightColor ?? widget.splashColor;
    if (_hovered) return widget.hoverColor;
    if (_focused) return widget.focusColor;
    return null;
  }

  void _handleTap() {
    if (widget.enableFeedback) Feedback.forTap(context);
    widget.onTap?.call();
  }

  void _handleLongPress() {
    if (widget.enableFeedback) Feedback.forLongPress(context);
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null ||
        widget.onDoubleTap != null ||
        widget.onLongPress != null;
    final cursor = widget.mouseCursor ??
        (_isDesktopPlatform && enabled
            ? SystemMouseCursors.click
            : MouseCursor.defer);

    Widget content = Stack(
      fit: StackFit.passthrough,
      children: [
        if (widget.child != null) widget.child!,
        if (_stateColor case final color?)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: color),
            ),
          ),
      ],
    );

    if (widget.borderRadius case final radius?) {
      content = ClipRRect(borderRadius: radius, child: content);
    }

    content = ShadGestureDetector(
      cursor: cursor,
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: widget.excludeFromSemantics,
      onHoverChange: (hovered) {
        _setStateFlag(WidgetState.hovered, hovered);
        widget.onHover?.call(hovered);
      },
      onTapDown: (_) => _setStateFlag(WidgetState.pressed, true),
      onTapUp: (_) => _setStateFlag(WidgetState.pressed, false),
      onTapCancel: () => _setStateFlag(WidgetState.pressed, false),
      onTap: widget.onTap == null ? null : _handleTap,
      onDoubleTap: widget.onDoubleTap,
      onLongPress: widget.onLongPress == null ? null : _handleLongPress,
      child: content,
    );

    if (!widget.canRequestFocus || !enabled) return content;

    return FocusableActionDetector(
      enabled: enabled,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      mouseCursor: cursor,
      onFocusChange: (focused) {
        _setStateFlag(WidgetState.focused, focused);
        widget.onFocusChange?.call(focused);
      },
      actions: widget.onTap == null
          ? const <Type, Action<Intent>>{}
          : <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _handleTap();
                  return null;
                },
              ),
            },
      child: content,
    );
  }
}

/// 桌面端自动显示手型鼠标的 GestureDetector。
///
/// 拖拽等纯行为能力继续使用 Flutter GestureDetector；这里不产生产品视觉。
class FxGestureDetector extends StatelessWidget {
  final Widget? child;
  final GestureTapCallback? onTap;
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureTapCallback? onTapCancel;
  final GestureTapCallback? onDoubleTap;
  final GestureLongPressCallback? onLongPress;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final GestureDragStartCallback? onHorizontalDragStart;
  final GestureDragUpdateCallback? onHorizontalDragUpdate;
  final GestureDragEndCallback? onHorizontalDragEnd;
  final HitTestBehavior? behavior;

  const FxGestureDetector({
    super.key,
    this.child,
    this.onTap,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
    this.onDoubleTap,
    this.onLongPress,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onHorizontalDragStart,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
    this.behavior,
  });

  bool get _hasInteraction =>
      onTap != null ||
      onDoubleTap != null ||
      onLongPress != null ||
      onTapDown != null ||
      onTapUp != null ||
      onPanStart != null ||
      onVerticalDragStart != null ||
      onHorizontalDragStart != null;

  @override
  Widget build(BuildContext context) {
    final detector = GestureDetector(
      onTap: onTap,
      onTapDown: onTapDown,
      onTapUp: onTapUp,
      onTapCancel: onTapCancel,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      onVerticalDragStart: onVerticalDragStart,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      onHorizontalDragStart: onHorizontalDragStart,
      onHorizontalDragUpdate: onHorizontalDragUpdate,
      onHorizontalDragEnd: onHorizontalDragEnd,
      behavior: behavior,
      child: child,
    );
    if (!_isDesktopPlatform || !_hasInteraction) return detector;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: detector,
    );
  }
}
