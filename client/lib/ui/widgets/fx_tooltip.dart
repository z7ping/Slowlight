import 'package:flutter/material.dart';

/// FxTooltip — 提示组件。
///
/// Tooltip 属于辅助交互语义，不应要求调用方额外提供 ShadTheme；
/// Fx 层统一屏蔽底层实现，保证普通 Material 测试壳和正式 ShadApp 都可使用。
class FxTooltip extends StatelessWidget {
  final Widget child;
  final String message;

  const FxTooltip({
    super.key,
    required this.child,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      child: child,
    );
  }
}
