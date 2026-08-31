import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Slowlight 统一分隔线。
///
/// 业务代码不直接依赖 Material Divider / VerticalDivider。兼容原 Divider
/// 的 height/width/indent/endIndent 布局语义，实际线条由 ShadSeparator 绘制。
class FxSeparator extends StatelessWidget {
  const FxSeparator.horizontal({
    super.key,
    this.height,
    this.indent,
    this.endIndent,
    this.margin,
    this.thickness,
    this.color,
    this.radius,
  })  : vertical = false,
        width = null;

  const FxSeparator.vertical({
    super.key,
    this.width,
    this.indent,
    this.endIndent,
    this.margin,
    this.thickness,
    this.color,
    this.radius,
  })  : vertical = true,
        height = null;

  final bool vertical;
  final double? height;
  final double? width;
  final double? indent;
  final double? endIndent;
  final EdgeInsets? margin;
  final double? thickness;
  final Color? color;
  final BorderRadiusGeometry? radius;

  @override
  Widget build(BuildContext context) {
    final effectiveThickness = thickness ?? 1;

    if (vertical) {
      Widget separator = ShadSeparator.vertical(
        margin: margin,
        thickness: effectiveThickness,
        color: color,
        radius: radius,
      );
      if (indent != null || endIndent != null) {
        separator = Padding(
          padding: EdgeInsets.only(
            top: indent ?? 0,
            bottom: endIndent ?? 0,
          ),
          child: separator,
        );
      }
      if (width != null) {
        separator = SizedBox(
          width: width,
          child: Center(child: separator),
        );
      }
      return separator;
    }

    Widget separator = ShadSeparator.horizontal(
      margin: margin,
      thickness: effectiveThickness,
      color: color,
      radius: radius,
    );
    if (indent != null || endIndent != null) {
      separator = Padding(
        padding: EdgeInsets.only(
          left: indent ?? 0,
          right: endIndent ?? 0,
        ),
        child: separator,
      );
    }
    if (height != null) {
      separator = SizedBox(
        height: height,
        child: Center(child: separator),
      );
    }
    return separator;
  }
}
