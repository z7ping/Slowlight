import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// FxCheckbox — 复选框组件
class FxCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final bool enabled;

  const FxCheckbox({
    super.key,
    required this.value,
    this.onChanged,
    this.label,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ShadCheckbox(
      value: value,
      onChanged: enabled ? onChanged : null,
      label: label != null ? Text(label!) : null,
    );
  }
}
