import 'package:flutter/material.dart';

/// FxBadge — 通知计数组件
class FxBadge extends StatelessWidget {
  final int count;
  final Widget child;
  final bool showZero;

  const FxBadge({
    super.key,
    required this.count,
    required this.child,
    this.showZero = false,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0 && !showZero) return child;
    return Badge(
      label: Text(count > 99 ? '99+' : '$count'),
      child: child,
    );
  }
}
