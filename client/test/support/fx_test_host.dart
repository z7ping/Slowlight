import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/ui/theme_manager.dart';

/// 测试用 Slowlight UI 根节点。
///
/// 与正式应用保持相同的关键视觉上下文：
/// ShadTheme → MaterialApp → FxNoticeHost。
Widget buildFxTestHost({
  required Widget home,
  ThemeData? theme,
  TransitionBuilder? builder,
}) {
  return ShadTheme(
    data: ThemeManager.shadLight,
    child: MaterialApp(
      theme: theme ?? ThemeManager.lightTheme,
      builder: (context, child) {
        final hosted = FxNoticeHost(child: child!);
        return builder == null ? hosted : builder(context, hosted);
      },
      home: home,
    ),
  );
}

/// 主动销毁 Fx 测试宿主，并推进一次虚拟时间。
///
/// shadcn/Sonner 与 flutter_animate 在入场、退场时可能创建零延时或短延时
/// Timer。Widget test 在回调结束前必须先卸载整棵 UI 树，否则会把正常的
/// 动画调度误报为 pending timer。这里统一承担测试环境的生命周期收尾。
Future<void> disposeFxTestHost(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}

Finder fxTooltipFinder(String message) => find.byWidgetPredicate(
      (widget) => widget is FxTooltip && widget.message == message,
      description: 'FxTooltip with message "$message"',
    );
