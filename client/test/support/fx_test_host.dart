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
}) {
  return ShadTheme(
    data: ThemeManager.shadLight,
    child: MaterialApp(
      theme: theme ?? ThemeManager.lightTheme,
      builder: (context, child) => FxNoticeHost(child: child!),
      home: home,
    ),
  );
}

Finder fxTooltipFinder(String message) => find.byWidgetPredicate(
      (widget) => widget is FxTooltip && widget.message == message,
      description: 'FxTooltip with message "$message"',
    );
