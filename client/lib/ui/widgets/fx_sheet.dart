import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../color_tokens.dart';

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
    bool isScrollControlled = true,
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
        Widget content = builder(sheetContext);
        if (useSafeArea) content = SafeArea(child: content);
        return ShadSheet(
          title: title,
          description: description,
          actions: actions,
          constraints: constraints,
          padding: padding,
          radius: radius,
          backgroundColor: backgroundColor,
          draggable: effectiveDraggable,
          isScrollControlled: isScrollControlled,
          child: content,
        );
      },
    );
  }
}
