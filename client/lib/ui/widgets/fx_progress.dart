import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// FxProgress — 统一进度反馈。
///
/// [value] 为 null 时使用 shadcn_ui 的不确定进度动画；否则取 0.0~1.0。
class FxProgress extends StatelessWidget {
  final double? value;
  final double? height;
  final Color? color;
  final Color? backgroundColor;
  final String? semanticsLabel;
  final String? semanticsValue;

  const FxProgress({
    super.key,
    this.value,
    this.height,
    this.color,
    this.backgroundColor,
    this.semanticsLabel,
    this.semanticsValue,
  });

  @override
  Widget build(BuildContext context) {
    return ShadProgress(
      value: value,
      minHeight: height,
      color: color,
      backgroundColor: backgroundColor,
      semanticsLabel: semanticsLabel,
      semanticsValue: semanticsValue,
    );
  }
}
