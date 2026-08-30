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
  static final Expando<Set<Object>> _shownIds = Expando<Set<Object>>();

  static Object? show(
    BuildContext context,
    String message, {
    String? description,
    Widget? action,
    Duration? duration,
    FxNoticeVariant variant = FxNoticeVariant.normal,
  }) {
    final sonner = _sonnerOf(context);
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
    final id = sonner.show(toast);
    if (id != null) {
      final ids = _shownIds[sonner] ??= <Object>{};
      ids.add(id);
      // Sonner 0.26.5 没有 clear-all API。只登记最近一批 Fx 通知，既能
      // 保留旧 ScaffoldMessenger.clearSnackBars() 语义，也避免长期运行时
      // 因已自动消失的 toast id 无限增长。
      while (ids.length > 64) {
        ids.remove(ids.first);
      }
    }
    return id;
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

  static Future<void> dismiss(BuildContext context, Object? id) async {
    if (id == null) return;
    final sonner = _sonnerOf(context);
    _shownIds[sonner]?.remove(id);
    await sonner.hide(id);
  }

  static Future<void> clear(BuildContext context) async {
    final sonner = _sonnerOf(context);
    final ids = _shownIds[sonner];
    if (ids == null || ids.isEmpty) return;

    final snapshot = List<Object>.of(ids);
    ids.clear();
    for (final id in snapshot) {
      await sonner.hide(id);
    }
  }

  static ShadSonnerState _sonnerOf(BuildContext context) {
    final sonner = ShadSonner.maybeOf(context);
    if (sonner == null) {
      throw FlutterError(
        'FxNoticeHost not found. Wrap the app content with FxNoticeHost.',
      );
    }
    return sonner;
  }
}
