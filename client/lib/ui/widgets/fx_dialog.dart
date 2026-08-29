import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// FxDialog — 弹窗组件
class FxDialog {
  static const Color barrierColor = Color(0x73000000);

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    String? description,
    double? width,
    bool barrierDismissible = true,
  }) {
    return showShadDialog<T>(
      context: context,
      barrierColor: barrierColor,
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      builder: (ctx) => ShadDialog(
        title: title != null ? Text(title) : null,
        description: description != null ? Text(description) : null,
        constraints: width != null ? BoxConstraints(maxWidth: width) : null,
        child: Material(
          type: MaterialType.transparency,
          child: child,
        ),
      ),
    );
  }

  /// 确认弹窗
  static Future<bool?> confirm({
    required BuildContext context,
    required String title,
    required String content,
    String confirmText = '确认',
    String cancelText = '取消',
    bool destructive = false,
    bool barrierDismissible = true,
  }) {
    return showShadDialog<bool>(
      context: context,
      barrierColor: barrierColor,
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      variant:
          destructive ? ShadDialogVariant.alert : ShadDialogVariant.primary,
      builder: (ctx) => ShadDialog(
        title: Text(title),
        description: Text(content),
        actions: [
          ShadButton.outline(
            child: Text(cancelText),
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
          ),
          destructive
              ? ShadButton.destructive(
                  child: Text(confirmText),
                  onPressed: () =>
                      Navigator.of(ctx, rootNavigator: true).pop(true),
                )
              : ShadButton(
                  child: Text(confirmText),
                  onPressed: () =>
                      Navigator.of(ctx, rootNavigator: true).pop(true),
                ),
        ],
      ),
    );
  }
}
