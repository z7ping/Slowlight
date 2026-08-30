import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// FxSlider — 统一滑块组件。
///
/// 业务页面通过 Fx 层使用 shadcn_ui 的 Slider，不直接依赖 Material Slider。
class FxSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final String? label;

  const FxSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return ShadSlider(
      initialValue: value,
      min: min,
      max: max,
      divisions: divisions,
      label: label,
      onChanged: onChanged,
      enabled: onChanged != null,
    );
  }
}
