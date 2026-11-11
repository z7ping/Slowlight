import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../color_tokens.dart';
import '../layout_tokens.dart';

/// Slowlight 统一 Sheet 入口。
///
/// 业务代码不直接调用 Material showModalBottomSheet。这里保留既有调用常见参数，
/// 由 Fx 层映射到 shadcn_ui，避免迁移时改变业务语义。
abstract final class FxSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    Widget? title,
    Widget? description,
    List<Widget> actions = const [],
    ShadSheetSide side = ShadSheetSide.bottom,
    bool dismissible = true,
    bool? isDismissible,
    bool useRootNavigator = false,
    bool draggable = true,
    bool? enableDrag,
    /// Explicitly controls the handle. When omitted, guarded editors show it.
    /// Ordinary draggable sheets show it only when explicitly requested.
    bool? showDragHandle,
    /// Invoked by a gesture starting in the top 44dp grip region. The owner
    /// decides whether a dirty draft may close; never pop behind its back.
    Future<void> Function()? onDismissRequested,
    bool showCloseButton = true,
    bool isScrollControlled = true,
    bool scrollable = false,
    bool useSafeArea = false,
    BoxConstraints? constraints,
    EdgeInsets? padding,
    Color? backgroundColor,
    Color? barrierColor,
    String? barrierLabel,
    ShapeBorder? shape,
    RouteSettings? routeSettings,
    Offset? anchorPoint,
  }) {
    final effectiveDismissible = isDismissible ?? dismissible;
    final effectiveDraggable = enableDrag ?? draggable;
    // Keep the render anchor stable across sheet rebuilds (e.g. keyboard).
    final gripRegionKey = GlobalKey();
    BorderRadius? radius;
    if (shape is RoundedRectangleBorder && shape.borderRadius is BorderRadius) {
      radius = shape.borderRadius as BorderRadius;
    }

    return showShadSheet<T>(
      context: context,
      side: side,
      backgroundColor: backgroundColor,
      barrierColor: barrierColor ?? SlowlightSemanticColor.sheetBarrier,
      barrierLabel: barrierLabel ??
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
      shape: shape,
      isDismissible: effectiveDismissible,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      anchorPoint: anchorPoint,
      builder: (sheetContext) {
        final platform = Theme.of(sheetContext).platform;
        final mobileBottom = side == ShadSheetSide.bottom &&
            (platform == TargetPlatform.android ||
             platform == TargetPlatform.iOS);
        final hasDismissGuard = onDismissRequested != null;
        final handleOnly = mobileBottom &&
            hasDismissGuard &&
            (showDragHandle ?? true);
        // A simple, safely dismissible action sheet may use ShadSheet's
        // native drag; its requested indicator was previously ignored.
        // Never show a dead drag affordance on non-draggable forms.
        final passiveHandle = mobileBottom &&
            !hasDismissGuard &&
            showDragHandle == true &&
            effectiveDraggable &&
            effectiveDismissible &&
            title == null;
        // Guarded forms never let ShadSheet drag the entire scrollable body,
        // even if their owner explicitly hides the handle.
        double dragDistance = 0;
        bool dragging = false;
        int? activePointer;
        double startY = 0;
        VelocityTracker? tracker;
        final reduceMotion = MediaQuery.of(sheetContext).disableAnimations;
        final viewInsets = MediaQuery.viewInsetsOf(sheetContext);
        final insetPadding = switch (side) {
          ShadSheetSide.bottom => EdgeInsets.only(bottom: viewInsets.bottom),
          ShadSheetSide.top => EdgeInsets.only(top: viewInsets.top),
          ShadSheetSide.left => EdgeInsets.only(left: viewInsets.left),
          ShadSheetSide.right => EdgeInsets.only(right: viewInsets.right),
        };

        Widget content = builder(sheetContext);
        if (useSafeArea) content = SafeArea(child: content);

        Widget buildSheet(Widget? grip) => ShadSheet(
          closeIcon: showCloseButton ? null : const SizedBox.shrink(),
          // Use the compact visual grip as the header; only its top 44dp
          // gesture band may request dismissal, leaving the body scrollable.
          title: grip ?? title,
          description: description,
          titleTextAlign: TextAlign.start,
          descriptionTextAlign: TextAlign.start,
          actions: actions,
          // Grip already occupies the header slot; add no duplicate gap.
          gap: grip != null ? 0 : null,
          constraints: constraints,
          padding: padding,
          radius: radius ?? (mobileBottom
              ? const BorderRadius.vertical(
                  top: Radius.circular(SlowlightRadius.xl))
              : null),
          backgroundColor: backgroundColor,
          // ShadDialog otherwise strips the painted radius below 640dp.
          removeBorderRadiusWhenTiny: mobileBottom ? false : null,
          draggable: hasDismissGuard && mobileBottom
              ? false
              : effectiveDraggable,
          isScrollControlled: isScrollControlled,
          scrollable: scrollable,
          child: content,
        );

        // Compact 24dp visual strip, 36x4dp indicator; drag starts remain
        // 44dp tall without allocating a 44dp header above the content.
        Widget gripIndicator({Key? key}) => SizedBox(
          key: key,
          width: double.infinity,
          height: SlowlightSpacing.page,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(sheetContext).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const SizedBox(width: 36, height: 4),
            ),
          ),
        );

        Widget sheet;
        if (!handleOnly) {
          sheet = buildSheet(passiveHandle
              ? gripIndicator(key: const ValueKey('fx.sheet.visualHandle'))
              : null);
        } else {
          sheet = StatefulBuilder(
            builder: (context, setDragState) {
              void reset() {
                activePointer = null;
                tracker = null;
                if (!dragging && dragDistance == 0) return;
                setDragState(() {
                  dragging = false;
                  dragDistance = 0;
                });
              }

              final grip = Semantics(
                label: '下滑关闭弹窗',
                button: true,
                // Accessibility dismissal follows the original draft guard.
                onTap: () {
                  onDismissRequested?.call();
                },
                child: SizedBox(
                  key: gripRegionKey,
                  child: gripIndicator(
                    key: const ValueKey('fx.sheet.dragHandle'),
                  ),
                ),
              );

              return AnimatedContainer(
                duration: dragging || reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 190),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(0, dragDistance, 0),
                // Listener preserves scroll/text selection recognizers; only
                // gestures beginning within 44dp of the visible grip count.
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (event) {
                    if (activePointer != null) return;
                    final render =
                        gripRegionKey.currentContext?.findRenderObject();
                    if (render is! RenderBox || !render.hasSize) return;
                    final top = render.localToGlobal(Offset.zero).dy;
                    if (event.position.dy < top ||
                        event.position.dy >
                            top + SlowlightControlSize.minTouchTarget) {
                      return;
                    }
                    activePointer = event.pointer;
                    startY = event.position.dy;
                    tracker = VelocityTracker.withKind(event.kind)
                      ..addPosition(event.timeStamp, event.position);
                  },
                  onPointerMove: (event) {
                    if (event.pointer != activePointer) return;
                    tracker?.addPosition(event.timeStamp, event.position);
                    final distance =
                        (event.position.dy - startY).clamp(0.0, 1000.0);
                    if (!dragging && distance <= 6) return;
                    if (!dragging) FocusScope.of(context).unfocus();
                    setDragState(() {
                      dragging = true;
                      dragDistance = distance;
                    });
                  },
                  onPointerUp: (event) async {
                    if (event.pointer != activePointer) return;
                    tracker?.addPosition(event.timeStamp, event.position);
                    final distance =
                        (event.position.dy - startY).clamp(0.0, 1000.0);
                    final speed =
                        tracker?.getVelocity().pixelsPerSecond.dy ?? 0;
                    final close = distance > 120 ||
                        (distance > 40 && speed > 750);
                    reset();
                    if (close) await onDismissRequested?.call();
                  },
                  onPointerCancel: (event) {
                    if (event.pointer == activePointer) reset();
                  },
                  child: buildSheet(grip),
                ),
              );
            },
          );
        }

        // 键盘开合时保持相同的组件树，避免重新挂载输入框、丢失焦点。
        return AnimatedPadding(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 200),
          curve: Curves.linearToEaseOut,
          padding: insetPadding,
          child: MediaQuery.removeViewInsets(
            context: sheetContext,
            removeBottom: side == ShadSheetSide.bottom,
            removeTop: side == ShadSheetSide.top,
            removeLeft: side == ShadSheetSide.left,
            removeRight: side == ShadSheetSide.right,
            child: sheet,
          ),
        );
      },
    );
  }
}
