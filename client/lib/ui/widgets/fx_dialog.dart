import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// FxDialog — 弹窗组件
class FxDialog {
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    String? description,
    double? width,
  }) {
    return showShadDialog<T>(
      context: context,
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
  }) {
    return showShadDialog<bool>(
      context: context,
      builder: (ctx) => ShadDialog(
        title: Text(title),
        description: Text(content),
        actions: [
          ShadButton.outline(
            child: Text(cancelText),
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
          ),
          ShadButton(
            child: Text(confirmText),
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
          ),
        ],
      ),
    );
  }
}
