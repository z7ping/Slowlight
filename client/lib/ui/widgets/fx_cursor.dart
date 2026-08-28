import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool get _isDesktopPlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

/// 桌面端自动显示手型鼠标的 InkWell
///
/// 移动端行为与普通 InkWell 一致。
/// 用于替代项目中所有 InkWell，统一桌面端交互体验。
class FxInkWell extends InkWell {
  FxInkWell({
    Key? key,
    Widget? child,
    GestureTapCallback? onTap,
    GestureTapCallback? onDoubleTap,
    GestureLongPressCallback? onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    MouseCursor? mouseCursor,
    BorderRadius? borderRadius,
    Color? highlightColor,
    Color? splashColor,
    Color? hoverColor,
    Color? focusColor,
    InteractiveInkFeatureFactory? splashFactory,
    double? radius,
    WidgetStateProperty<Color?>? overlayColor,
    bool enableFeedback = true,
    bool excludeFromSemantics = false,
    bool canRequestFocus = true,
    bool autofocus = false,
    FocusNode? focusNode,
    WidgetStatesController? statesController,
  }) : super(
    key: key,
    child: child,
    onTap: onTap,
    onDoubleTap: onDoubleTap,
    onLongPress: onLongPress,
    onHover: onHover,
    onFocusChange: onFocusChange,
    mouseCursor: mouseCursor ?? (_isDesktopPlatform ? SystemMouseCursors.click : MouseCursor.defer),
    borderRadius: borderRadius,
    highlightColor: highlightColor,
    splashColor: splashColor,
    hoverColor: hoverColor,
    focusColor: focusColor,
    splashFactory: splashFactory,
    radius: radius,
    overlayColor: overlayColor,
    enableFeedback: enableFeedback,
    excludeFromSemantics: excludeFromSemantics,
    canRequestFocus: canRequestFocus,
    autofocus: autofocus,
    focusNode: focusNode,
    statesController: statesController,
  );
}

/// 桌面端自动显示手型鼠标的 GestureDetector
///
/// 移动端行为与普通 GestureDetector 一致。
/// 通过 MouseRegion 包装实现手型光标，而非继承。
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
      onTap != null || onDoubleTap != null || onLongPress != null ||
      onTapDown != null || onTapUp != null ||
      onPanStart != null || onVerticalDragStart != null || onHorizontalDragStart != null;

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
