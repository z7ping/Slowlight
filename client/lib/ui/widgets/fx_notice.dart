import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Slowlight 全局通知承载层。
///
/// 应放在应用根部，使业务页面统一通过 [FxNotice] 展示轻量反馈。
class FxNoticeHost extends StatelessWidget {
  const FxNoticeHost({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) => ShadSonner(child: child);
}

enum FxNoticeVariant {
  normal,
  destructive,
}

/// Slowlight 统一轻量通知入口。
///
/// 业务页面不直接创建 SnackBar / ScaffoldMessenger。
abstract final class FxNotice {
  static Object? show(
    BuildContext context,
    String message, {
    String? description,
    Widget? action,
    Duration? duration,
    FxNoticeVariant variant = FxNoticeVariant.normal,
  }) {
    final sonner = ShadSonner.maybeOf(context);
    if (sonner == null) {
      throw FlutterError(
        'FxNoticeHost not found. Wrap the app content with FxNoticeHost.',
      );
    }

    final toast = switch (variant) {
      FxNoticeVariant.normal => ShadToast(
          title: Text(message),
          description: description == null ? null : Text(description),
          action: action,
          duration: duration,
        ),
      FxNoticeVariant.destructive => ShadToast.destructive(
          title: Text(message),
          description: description == null ? null : Text(description),
          action: action,
          duration: duration,
        ),
    };
    return sonner.show(toast);
  }

  static Object? error(
    BuildContext context,
    String message, {
    String? description,
    Widget? action,
    Duration? duration,
  }) =>
      show(
        context,
        message,
        description: description,
        action: action,
        duration: duration,
        variant: FxNoticeVariant.destructive,
      );
}
