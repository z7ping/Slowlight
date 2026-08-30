import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../typography_tokens.dart';

/// FxDialog — 统一弹窗组件。
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
        title: title != null
            ? Text(
                title,
                style: SlowlightTypography.cardTitle(ctx).copyWith(
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
        description: description != null
            ? Text(
                description,
                style: SlowlightTypography.secondary(ctx).copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        constraints: width != null ? BoxConstraints(maxWidth: width) : null,
        child: Material(
          type: MaterialType.transparency,
          child: child,
        ),
      ),
    );
  }

  /// 确认弹窗。
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
        title: Text(
          title,
          style: SlowlightTypography.cardTitle(ctx).copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        description: Text(
          content,
          style: SlowlightTypography.secondary(ctx).copyWith(
            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: Text(cancelText, style: SlowlightTypography.button),
          ),
          destructive
              ? ShadButton.destructive(
                  onPressed: () =>
                      Navigator.of(ctx, rootNavigator: true).pop(true),
                  child: Text(confirmText, style: SlowlightTypography.button),
                )
              : ShadButton(
                  onPressed: () =>
                      Navigator.of(ctx, rootNavigator: true).pop(true),
                  child: Text(confirmText, style: SlowlightTypography.button),
                ),
        ],
      ),
    );
  }
}
