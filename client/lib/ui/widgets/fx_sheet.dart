import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Slowlight 统一 Sheet 入口。
///
/// 业务代码不直接调用 Material showModalBottomSheet。
abstract final class FxSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    Widget? title,
    Widget? description,
    List<Widget> actions = const [],
    ShadSheetSide side = ShadSheetSide.bottom,
    bool dismissible = true,
    bool useRootNavigator = false,
    bool draggable = true,
    bool isScrollControlled = true,
    BoxConstraints? constraints,
    EdgeInsets? padding,
  }) {
    return showShadSheet<T>(
      context: context,
      side: side,
      isDismissible: dismissible,
      useRootNavigator: useRootNavigator,
      builder: (sheetContext) => ShadSheet(
        title: title,
        description: description,
        actions: actions,
        constraints: constraints,
        padding: padding,
        draggable: draggable,
        isScrollControlled: isScrollControlled,
        child: builder(sheetContext),
      ),
    );
  }
}
