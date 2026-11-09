import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../services/app_error_logger.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../app_theme.dart';
import '../color_tokens.dart';
import '../layout_tokens.dart';
import 'fx_button.dart';

/// Slowlight 全局通知承载层。
///
/// 应放在应用根部，使业务页面统一通过 [FxNotice] 展示轻量反馈。
class FxNoticeHost extends StatefulWidget {
  const FxNoticeHost({super.key, required this.child});

  final Widget child;

  @override
  State<FxNoticeHost> createState() => _FxNoticeHostState();
}

class _FxNoticeHostState extends State<FxNoticeHost> {
  final _undoKey = GlobalKey<ShadSonnerState>();

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final safePadding = mediaQuery.viewPadding;
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final mobile = SlowlightPlatformDensity.usesMobileTouchTargets;
    const edge = SlowlightSpacing.xxxl;
    final bottomInset = keyboardInset > safePadding.bottom
        ? keyboardInset
        : safePadding.bottom;
    // 移动端撤销浮层保留底栏空间；键盘出现时优先避让输入法。
    final bottomNavReserve = mobile && keyboardInset <= safePadding.bottom
        ? SlowlightControlSize.minTouchTarget + edge
        : 0.0;

    return ShadSonner(
      key: _undoKey,
      alignment: mobile ? Alignment.bottomCenter : Alignment.bottomRight,
      visibleToastsAmount: 3,
      animationDuration: const Duration(milliseconds: 180),
      padding: EdgeInsets.fromLTRB(
        edge + safePadding.left,
        edge + safePadding.top,
        edge + safePadding.right,
        edge + bottomInset + bottomNavReserve,
      ),
      child: ShadSonner(
        alignment: mobile ? Alignment.topCenter : Alignment.topRight,
        visibleToastsAmount: 3,
        animationDuration: const Duration(milliseconds: 180),
        padding: EdgeInsets.fromLTRB(
          edge + safePadding.left,
          edge + safePadding.top,
          edge + safePadding.right,
          edge,
        ),
        child: _FxNoticeUndoScope(undoKey: _undoKey, child: widget.child),
      ),
    );
  }
}

/// 在不改变业务调用的前提下，让撤销通知使用独立的底部 Sonner。
class _FxNoticeUndoScope extends InheritedWidget {
  const _FxNoticeUndoScope({required this.undoKey, required super.child});

  final GlobalKey<ShadSonnerState> undoKey;

  @override
  bool updateShouldNotify(_FxNoticeUndoScope oldWidget) =>
      undoKey != oldWidget.undoKey;
}

enum FxNoticePlacement { top, undo }

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
  const FxNoticeHandle._(this._topSonner, this._undoSonner);

  final ShadSonnerState _topSonner;
  final ShadSonnerState _undoSonner;

  ShadSonnerState _target(FxNoticePlacement placement) =>
      placement == FxNoticePlacement.undo ? _undoSonner : _topSonner;

  Object? show(
    String message, {
    String? description,
    Widget? action,
    Duration? duration,
    FxNoticeVariant variant = FxNoticeVariant.normal,
    FxNoticePlacement placement = FxNoticePlacement.top,
  }) =>
      FxNotice._showWithSonner(
        _target(placement),
        Text(message),
        description: description == null ? null : Text(description),
        action: action,
        duration: duration,
        variant: variant,
        placement: placement,
      );

  Object? showContent(
    Widget content, {
    Widget? description,
    Widget? action,
    Duration? duration,
    FxNoticeVariant variant = FxNoticeVariant.normal,
    FxNoticePlacement placement = FxNoticePlacement.top,
  }) =>
      FxNotice._showWithSonner(
        _target(placement),
        content,
        description: description,
        action: action,
        duration: duration,
        variant: variant,
        placement: placement,
      );

  Future<void> dismiss(Object? id) async {
    await Future.wait([
      FxNotice._dismissWithSonner(_topSonner, id),
      FxNotice._dismissWithSonner(_undoSonner, id),
    ]);
  }

  Future<void> clear() async {
    await Future.wait([
      FxNotice._clearWithSonner(_topSonner),
      FxNotice._clearWithSonner(_undoSonner),
    ]);
  }
}

/// Slowlight 统一轻量通知入口。
///
/// 业务页面不直接创建 SnackBar / ScaffoldMessenger。
abstract final class FxNotice {
  static final Expando<Set<Object>> _shownIds = Expando<Set<Object>>();

  static FxNoticeHandle capture(BuildContext context) =>
      FxNoticeHandle._(
        _sonnerOf(context, FxNoticePlacement.top),
        _sonnerOf(context, FxNoticePlacement.undo),
      );

  static Object? show(
    BuildContext context,
    String message, {
    String? description,
    Widget? action,
    Duration? duration,
    FxNoticeVariant variant = FxNoticeVariant.normal,
    FxNoticePlacement placement = FxNoticePlacement.top,
  }) =>
      _showWithSonner(
        _sonnerOf(context, placement),
        Text(message),
        description: description == null ? null : Text(description),
        action: action,
        duration: duration,
        variant: variant,
        placement: placement,
      );

  static Object? showContent(
    BuildContext context,
    Widget content, {
    Widget? description,
    Widget? action,
    Duration? duration,
    FxNoticeVariant variant = FxNoticeVariant.normal,
    FxNoticePlacement placement = FxNoticePlacement.top,
  }) =>
      _showWithSonner(
        _sonnerOf(context, placement),
        content,
        description: description,
        action: action,
        duration: duration,
        variant: variant,
        placement: placement,
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
  }) {
    if (!kIsWeb) {
      AppErrorLogger.instance.write(
        source: 'UI',
        error: description == null ? message : '$message：$description',
      );
    }
    return show(
      context,
      message,
      description: description,
      action: action,
      duration: duration,
      variant: FxNoticeVariant.destructive,
    );
  }

  /// 长错误只在通知中显示简短标题，完整异常  /// 错误详情留在诊断日志；轻量反馈不打开第二层 Dialog。
  static void recordError(String title, Object details) {
    if (!kIsWeb) {
      AppErrorLogger.instance.write(source: 'UI $title', error: details.toString());
    }
  }

  /// 仅将可阅读的短中文业务消息交给 UI，异常栈与内部实现不向用户展示。
  @visibleForTesting
  static String readableError(Object details) {
    final message = details.toString().trim().replaceFirst(
      RegExp(r'^(?:Exception|Bad state|FormatException):\s*'),
      '',
    ).trim();
    if (message.isEmpty ||
        message.length > 100 ||
        message.contains('\n') ||
        !RegExp(r'[\u3400-\u9fff]').hasMatch(message) ||
        RegExp(r'(?:Exception|StackTrace|#[0-9]+\s|dart:|https?://)', caseSensitive: false)
            .hasMatch(message)) {
      return '操作未完成，请稍后重试或到应用诊断查看记录';
    }
    return message;
  }

  /// 兼容原有调用：保留完整诊断记录，通知仅显示安全的短错误信息。
  static Object? errorWithDetails(
    BuildContext context,
    String title,
    String details,
  ) {
    recordError(title, details);
    return show(
      context,
      title,
      description: readableError(details),
      variant: FxNoticeVariant.destructive,
    );
  }

  static Future<void> dismiss(BuildContext context, Object? id) =>
      capture(context).dismiss(id);

  static Future<void> clear(BuildContext context) =>
      capture(context).clear();

  static Object? _showWithSonner(
    ShadSonnerState sonner,
    Widget content, {
    required Widget? description,
    required Widget? action,
    required Duration? duration,
    required FxNoticeVariant variant,
    FxNoticePlacement placement = FxNoticePlacement.top,
  }) {
    final ids = _shownIds[sonner] ??= <Object>{};
    // Sonner 会暂存超出可见上限的旧消息；主动关闭旧提示，避免重播。
    for (final id in List<Object>.of(ids)) {
      unawaited(sonner.hide(id));
    }
    ids.clear();
    final toast = _buildToast(
      content,
      description: description,
      action: action,
      duration: duration ?? (placement == FxNoticePlacement.undo
          ? const Duration(seconds: 8)
          : const Duration(milliseconds: 2500)),
      variant: variant,
      placement: placement,
    );
    final id = sonner.show(toast);
    if (id != null) {
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
    required FxNoticePlacement placement,
  }) {
    final alignment = placement == FxNoticePlacement.undo
        ? Alignment.bottomCenter
        : Alignment.topCenter;
    return switch (variant) {
      FxNoticeVariant.normal => ShadToast(
          alignment: alignment,
          title: content,
          description: description,
          action: action,
          duration: duration,
        ),
      FxNoticeVariant.destructive => ShadToast.destructive(
          alignment: alignment,
          title: content,
          description: description,
          action: action,
          duration: duration,
        ),
      FxNoticeVariant.success => ShadToast(
          alignment: alignment,
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
          alignment: alignment,
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

  static ShadSonnerState _sonnerOf(
    BuildContext context,
    FxNoticePlacement placement,
  ) {
    if (placement == FxNoticePlacement.undo) {
      final scope = context.dependOnInheritedWidgetOfExactType<_FxNoticeUndoScope>();
      final sonner = scope?.undoKey.currentState;
      if (sonner != null) return sonner;
    } else {
      final sonner = ShadSonner.maybeOf(context);
      if (sonner != null) return sonner;
    }
    throw FlutterError('FxNoticeHost not found. Wrap the app content with FxNoticeHost.');
  }

}
