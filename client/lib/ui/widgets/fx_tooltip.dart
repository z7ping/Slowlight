import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// FxTooltip — 提示组件
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
    return ShadTooltip(
      builder: (context) => Text(message),
      child: child,
    );
  }
}
