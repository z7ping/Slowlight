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
    bool? showDragHandle,
    /// Invoked by the 44dp grip only. The owner decides whether a dirty
    /// draft may close; FxSheet must never pop an editor behind its back.
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
    BorderRadius? radius;
    if (shape is RoundedRectangleBorder && shape.borderRadius is BorderRadius) {
      radius = shape.borderRadius as BorderRadius;
    }

    // showDragHandle 仅用于兼容旧 Material 调用。shadcn_ui 0.26.5 没有等价的
    // 独立 drag-handle 开关；拖拽能力仍由 draggable / enableDrag 控制。
    final _ = showDragHandle;

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
        final handleOnly = side == ShadSheetSide.bottom &&
            onDismissRequested != null &&
            (platform == TargetPlatform.android ||
             platform == TargetPlatform.iOS);
        // ShadSheet 0.26.x drags the entire surface, including scrollable
        // forms. The approved Android behavior is a handle-only gesture.
        double dragDistance = 0;
        bool dragging = false;
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
          // The approved grip occupies its own hit area; editing content
          // remains scrollable and cannot accidentally dismiss the sheet.
          title: grip ?? title,
          description: description,
          actions: actions,
          constraints: constraints,
          padding: padding,
          radius: handleOnly
              ? const BorderRadius.vertical(
                  top: Radius.circular(SlowlightRadius.xl))
              : radius,
          backgroundColor: backgroundColor,
          draggable: handleOnly ? false : effectiveDraggable,
          isScrollControlled: isScrollControlled,
          scrollable: scrollable,
          child: content,
        );

        Widget sheet;
        if (!handleOnly) {
          sheet = buildSheet(null);
        } else {
          sheet = StatefulBuilder(
            builder: (context, setDragState) {
              void reset() => setDragState(() {
                dragging = false;
                dragDistance = 0;
              });
              final grip = Semantics(
                label: '下滑关闭弹窗',
                button: true,
                // TalkBack/VoiceOver can invoke dismissal explicitly. A
                // single accidental touch on the grip never closes the form.
                onTap: () {
                  onDismissRequested?.call();
                },
                child: GestureDetector(
                  key: const ValueKey('fx.sheet.dragHandle'),
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (_) {
                    FocusScope.of(context).unfocus();
                    setDragState(() {
                      dragging = true;
                      dragDistance = 0;
                    });
                  },
                  onVerticalDragUpdate: (details) {
                    setDragState(() {
                      dragDistance =
                          (dragDistance + details.delta.dy).clamp(0.0, 1000.0);
                    });
                  },
                  onVerticalDragEnd: (details) async {
                    final close = dragDistance > 120 ||
                        (dragDistance > 40 &&
                         (details.primaryVelocity ?? 0) > 750);
                    reset();
                    if (close) await onDismissRequested?.call();
                  },
                  onVerticalDragCancel: reset,
                  child: SizedBox(
                    width: double.infinity,
                    height: SlowlightControlSize.minTouchTarget,
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const SizedBox(width: 36, height: 4),
                      ),
                    ),
                  ),
                ),
              );
              return AnimatedContainer(
                duration: dragging || reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 190),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(0, dragDistance, 0),
                child: buildSheet(grip),
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
