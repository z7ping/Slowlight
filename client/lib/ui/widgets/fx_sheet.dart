import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
    final radius = switch (shape) {
      RoundedRectangleBorder(borderRadius: final BorderRadiusGeometry value)
          when value is BorderRadius =>
        value,
      _ => null,
    };

    return showShadSheet<T>(
      context: context,
      side: side,
      backgroundColor: backgroundColor,
      barrierColor: barrierColor ?? const Color(0xcc000000),
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
