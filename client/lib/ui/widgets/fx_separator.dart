import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Slowlight 统一分隔线。
///
/// 业务代码不直接依赖 Material Divider / VerticalDivider。
class FxSeparator extends StatelessWidget {
  const FxSeparator.horizontal({
    super.key,
    this.margin,
    this.thickness,
    this.color,
    this.radius,
  }) : vertical = false;

  const FxSeparator.vertical({
    super.key,
    this.margin,
    this.thickness,
    this.color,
    this.radius,
  }) : vertical = true;

  final bool vertical;
  final EdgeInsets? margin;
  final double? thickness;
  final Color? color;
  final BorderRadiusGeometry? radius;

  @override
  Widget build(BuildContext context) {
    if (vertical) {
      return ShadSeparator.vertical(
        margin: margin,
        thickness: thickness,
        color: color,
        radius: radius,
      );
    }
    return ShadSeparator.horizontal(
      margin: margin,
      thickness: thickness,
      color: color,
      radius: radius,
    );
  }
}
