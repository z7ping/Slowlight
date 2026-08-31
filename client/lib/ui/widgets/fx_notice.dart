import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../app_theme.dart';
import '../color_tokens.dart';
import 'fx_button.dart';

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
  success,
  warning,
  destructive,
}

/// 通知内的小型动作按钮，例如“撤销”。
class FxNoticeAction extends StatelessWidget {
  const FxNoticeAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FxButton(
        label: label,
        onPressed: onPressed,
        variant: FxButtonVariant.ghost,
        size: FxButtonSize.sm,
      );
}

/// 在 Dialog / Sheet 关闭前捕获的通知句柄。
///
/// 它直接持有 Sonner 状态，因此关闭当前 Route 后仍能安全展示反馈，等价于
/// 旧代码提前缓存 ScaffoldMessengerState 的使用方式。
class FxNoticeHandle {
  const FxNoticeHandle._(this._sonner);

  final ShadSonnerState _sonner;

  Object? show(
    String message, {
    String? description,
    Widget? action,
    Duration? duration,
    FxNoticeVariant variant = FxNoticeVariant.normal,
  }) =>
      FxNotice._showWithSonner(
        _sonner,
        Text(message),
        description: description == null ? null : Text(description),
        action: action,
        duration: duration,
        variant: variant,
      );

  Object? showContent(
    Widget content, {
    Widget? description,
    Widget? action,
    Duration? duration,
    FxNoticeVariant variant = FxNoticeVariant.normal,
  }) =>
      FxNotice._showWithSonner(
        _sonner,
        content,
        description: description,
        action: action,
        duration: duration,
        variant: variant,
      );

  Future<void> dismiss(Object? id) => FxNotice._dismissWithSonner(_sonner, id);

  Future<void> clear() => FxNotice._clearWithSonner(_sonner);
}

/// Slowlight 统一轻量通知入口。
///
/// 业务页面不直接创建 SnackBar / ScaffoldMessenger。
abstract final class FxNotice {
  static final Expando<Set<Object>> _shownIds = Expando<Set<Object>>();

  static FxNoticeHandle capture(BuildContext context) =>
      FxNoticeHandle._(_sonnerOf(context));

  static Object? show(
    BuildContext context,
    String message, {
    String? description,
    Widget? action,
    Duration? duration,
    FxNoticeVariant variant = FxNoticeVariant.normal,
  }) =>
      _showWithSonner(
        _sonnerOf(context),
        Text(message),
        description: description == null ? null : Text(description),
        action: action,
        duration: duration,
        variant: variant,
      );

  static Object? showContent(
    BuildContext context,
    Widget content, {
    Widget? description,
    Widget? action,
    Duration? duration,
    FxNoticeVariant variant = FxNoticeVariant.normal,
  }) =>
      _showWithSonner(
        _sonnerOf(context),
        content,
        description: description,
        action: action,
        duration: duration,
        variant: variant,
      );

  static Object? success(
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
        variant: FxNoticeVariant.success,
      );

  static Object? warning(
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
        variant: FxNoticeVariant.warning,
      );

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

  static Future<void> dismiss(BuildContext context, Object? id) =>
      _dismissWithSonner(_sonnerOf(context), id);

  static Future<void> clear(BuildContext context) =>
      _clearWithSonner(_sonnerOf(context));

  static Object? _showWithSonner(
    ShadSonnerState sonner,
    Widget content, {
    required Widget? description,
    required Widget? action,
    required Duration? duration,
    required FxNoticeVariant variant,
  }) {
    final toast = _buildToast(
      content,
      description: description,
      action: action,
      duration: duration,
      variant: variant,
    );
    final id = sonner.show(toast);
    if (id != null) {
      final ids = _shownIds[sonner] ??= <Object>{};
      ids.add(id);
      // Sonner 0.26.5 没有 clear-all API。只登记最近一批 Fx 通知，既能
      // 保留旧 clearSnackBars() 语义，也避免长期运行时因已自动消失的
      // toast id 无限增长。
      while (ids.length > 64) {
        ids.remove(ids.first);
      }
    }
    return id;
  }

  static Future<void> _dismissWithSonner(
    ShadSonnerState sonner,
    Object? id,
  ) async {
    if (id == null) return;
    _shownIds[sonner]?.remove(id);
    await sonner.hide(id);
  }

  static Future<void> _clearWithSonner(ShadSonnerState sonner) async {
    final ids = _shownIds[sonner];
    if (ids == null || ids.isEmpty) return;

    final snapshot = List<Object>.of(ids);
    ids.clear();
    for (final id in snapshot) {
      await sonner.hide(id);
    }
  }

  static ShadToast _buildToast(
    Widget content, {
    required Widget? description,
    required Widget? action,
    required Duration? duration,
    required FxNoticeVariant variant,
  }) {
    return switch (variant) {
      FxNoticeVariant.normal => ShadToast(
          title: content,
          description: description,
          action: action,
          duration: duration,
        ),
      FxNoticeVariant.destructive => ShadToast.destructive(
          title: content,
          description: description,
          action: action,
          duration: duration,
        ),
      FxNoticeVariant.success => ShadToast(
          title: content,
          description: description,
          action: action,
          duration: duration,
          backgroundColor: AppTheme.success,
          border: const Border.fromBorderSide(
            BorderSide(color: AppTheme.success),
          ),
          titleStyle: const TextStyle(color: SlowlightSemanticColor.noticeSuccessForeground),
          descriptionStyle: const TextStyle(color: SlowlightSemanticColor.noticeSuccessForeground),
        ),
      FxNoticeVariant.warning => ShadToast(
          title: content,
          description: description,
          action: action,
          duration: duration,
          backgroundColor: AppTheme.warning,
          border: const Border.fromBorderSide(
            BorderSide(color: AppTheme.warning),
          ),
          titleStyle: const TextStyle(color: SlowlightSemanticColor.noticeWarningForeground),
          descriptionStyle: const TextStyle(color: SlowlightSemanticColor.noticeWarningForeground),
        ),
    };
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
