import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Slowlight 下拉刷新适配层。
///
/// Flutter 当前没有与 RefreshIndicator 等价的纯 widgets 基础设施，
/// shadcn_ui 0.26.5 也未提供 pull-to-refresh，因此 Material 实现只允许
/// 封装在这里；Feature / Screen 不直接依赖它。
class FxRefresh extends StatelessWidget {
  const FxRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
    this.displacement = 40,
    this.edgeOffset = 0,
    this.color,
    this.backgroundColor,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.semanticsLabel,
    this.semanticsValue,
    this.strokeWidth = RefreshProgressIndicator.defaultStrokeWidth,
    this.triggerMode = RefreshIndicatorTriggerMode.onEdge,
  });

  final Widget child;
  final RefreshCallback onRefresh;
  final double displacement;
  final double edgeOffset;
  final Color? color;
  final Color? backgroundColor;
  final ScrollNotificationPredicate notificationPredicate;
  final String? semanticsLabel;
  final String? semanticsValue;
  final double strokeWidth;
  final RefreshIndicatorTriggerMode triggerMode;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      displacement: displacement,
      edgeOffset: edgeOffset,
      color: color ?? theme.colorScheme.primary,
      backgroundColor: backgroundColor ?? theme.colorScheme.background,
      notificationPredicate: notificationPredicate,
      semanticsLabel: semanticsLabel,
      semanticsValue: semanticsValue,
      strokeWidth: strokeWidth,
      triggerMode: triggerMode,
      child: child,
    );
  }
}
