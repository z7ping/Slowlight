import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// FxProgress — 进度条组件
class FxProgress extends StatelessWidget {
  final double value; // 0.0 ~ 1.0
  final double? height;
  final Color? color;
  final Color? backgroundColor;

  const FxProgress({
    super.key,
    required this.value,
    this.height,
    this.color,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return ShadProgress(
      value: value,
      minHeight: height,
      color: color,
      backgroundColor: backgroundColor,
    );
  }
}
